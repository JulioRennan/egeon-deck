import Darwin
import Foundation

/// Socket de controle no diretório do flavor: `~/.egeon/sock`, ou
/// `~/.egeon-dev/sock` na cópia de desenvolvimento.
///
/// Unix domain socket, não porta TCP — nada exposto na rede. Fala HTTP/1.1
/// mínimo só para permitir testar com `curl --unix-socket` antes de existir
/// qualquer extensão do VSCode.
///
///   curl --unix-socket ~/.egeon/sock -X POST http://eg/dispatch \
///        -d '{"target":"deck/claude-1","kind":"raw","text":"oi"}'
///   curl --unix-socket ~/.egeon/sock http://eg/targets
final class ControlSocket {
    static let path = Flavor.current.config("sock").path

    private var listenFD: Int32 = -1

    /// Duas filas de propósito: `acceptLoop` roda um laço infinito e ocuparia a
    /// fila para sempre. Se os handlers usassem a mesma fila serial, todo
    /// atendimento ficaria enfileirado atrás do laço e nunca executaria.
    private let acceptQueue = DispatchQueue(label: "\(Flavor.current.identifier).control.accept", qos: .utility)
    private let workQueue = DispatchQueue(label: "\(Flavor.current.identifier).control.work",
                                          qos: .utility, attributes: .concurrent)

    func start() {
        try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: Self.path).deletingLastPathComponent(),
            withIntermediateDirectories: true)
        unlink(Self.path)

        guard Self.path.utf8.count < 104 else {
            Log.write("socket: caminho longo demais para sockaddr_un (\(Self.path))")
            return
        }

        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else {
            Log.write("socket: socket() falhou: \(String(cString: strerror(errno)))")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { tuple in
            tuple.withMemoryRebound(to: CChar.self, capacity: 104) { dest in
                _ = strcpy(dest, Self.path)
            }
        }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) { raw in
            raw.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenFD, $0, size) }
        }
        guard bound == 0, listen(listenFD, 16) == 0 else {
            Log.write("socket: bind/listen falhou: \(String(cString: strerror(errno)))")
            close(listenFD)
            listenFD = -1
            return
        }

        Log.write("socket: escutando em \(Self.path)")
        acceptQueue.async { [weak self] in self?.acceptLoop() }
    }

    func stop() {
        if listenFD >= 0 { close(listenFD) }
        unlink(Self.path)
    }

    private func acceptLoop() {
        while listenFD >= 0 {
            let clientFD = accept(listenFD, nil, nil)
            guard clientFD >= 0 else {
                if errno == EINTR { continue }
                return
            }
            workQueue.async { [weak self] in self?.handle(clientFD) }
        }
    }

    // MARK: - HTTP mínimo

    private func handle(_ fd: Int32) {
        defer { close(fd) }
        guard let (head, body) = readRequest(fd) else { return }

        let requestLine = head.split(separator: "\r\n").first.map(String.init) ?? ""
        let parts = requestLine.split(separator: " ").map(String.init)
        let method = parts.first ?? ""
        let route = parts.count > 1 ? parts[1] : ""

        // Rota sem a query. `/targets?folder=…` não termina em "/targets", e o
        // pedido cairia direto no 404.
        let bare = route.split(separator: "?").first.map(String.init) ?? route

        switch (method, bare.hasSuffix("/targets"), bare.hasSuffix("/dispatch")) {
        case ("GET", true, _):
            // `folder` é como a extensão do editor pergunta "quem posso acionar
            // DAQUI": sem ele a lista é global, e o editor de um projeto
            // oferecia terminal de outro, que não tem nada a ver com o arquivo
            // aberto. `all` acompanha para quem escolhe de propósito atravessar
            // sessão continuar podendo.
            let folder = Self.query(in: route)["folder"] ?? ""
            let payload = DispatchQueue.main.sync { () -> [String: Any] in
                let all = Dispatcher.shared.activeAddresses
                guard !folder.isEmpty else { return ["targets": all, "all": all] }
                let session = AppControl.sessionOwning?(folder) ?? ""
                return ["targets": session.isEmpty
                            ? [] : all.filter { $0.hasPrefix(session + "/") },
                        "all": all,
                        "session": session]
            }
            respond(fd, status: "200 OK", json: payload)

        case ("POST", _, _) where route.contains("/session"):
            // /session?target=sessão/id&id=<uuid> — o CLI relatando qual conversa
            // está aberta. Vem do gancho `UserPromptSubmit`, a cada prompt.
            let query = Self.query(in: route)
            let target = query["target"] ?? ""
            let id = query["id"] ?? ""
            guard !target.isEmpty, !id.isEmpty else {
                respond(fd, status: "400 Bad Request",
                        json: ["ok": false, "error": "target e id são obrigatórios"])
                return
            }
            DispatchQueue.main.sync { AppControl.recordSession?(target, id) }
            respond(fd, status: "200 OK", json: ["ok": true])

        case ("POST", _, _) where route.contains("/message"):
            // /message?from=<id>&target=<sessão/id> — corpo é o texto puro.
            //
            // Rota separada do /dispatch porque quem chama aqui é um agente,
            // escrevendo por um heredoc: montar JSON à mão significa escapar
            // aspas e quebras de linha no meio de um texto livre, e é onde ele
            // erra. Aqui o corpo é o texto e pronto.
            let query = Self.query(in: route)
            var request = DispatchRequest(target: query["target"] ?? "")
            request.text = String(decoding: body, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            deliver(request, to: fd)

        case ("GET", _, _) where route.contains("/peers"):
            // /peers — quem QUEM PERGUNTA pode acionar. Sem parâmetro de
            // identidade: o remetente sai do processo do outro lado do socket.
            let peers = DispatchQueue.main.sync { () -> [[String: Any]] in
                guard let origin = Dispatcher.shared.session(callingOn: fd) else { return [] }
                return Dispatcher.shared.peers(of: origin.address).map { peer in
                    var entry: [String: Any] = ["address": peer.address, "cli": peer.cli]
                    if let role = peer.role { entry["role"] = role }
                    return entry
                }
            }
            respond(fd, status: "200 OK", json: ["peers": peers])

        case ("GET", _, _) where route.contains("/status"):
            // /status — este terminal, do ponto de vista do app.
            let payload = DispatchQueue.main.sync { () -> [String: Any] in
                guard let origin = Dispatcher.shared.session(callingOn: fd) else {
                    return ["detail": "esta conexão não veio de um terminal"]
                }
                return ["address": origin.address,
                        "pending": origin.pending,
                        "peers": Dispatcher.shared.peers(of: origin.address).count]
            }
            respond(fd, status: "200 OK", json: payload)

        case ("GET", _, _) where route.contains("/geometry"):
            // /geometry — onde cada nó está na tela, para dirigir gestos de fora.
            let payload = DispatchQueue.main.sync { AppControl.canvasGeometry?() ?? [:] }
            respond(fd, status: "200 OK", json: payload)

        case ("GET", _, _) where route.contains("/peek"):
            // /peek?target=ws/id — mostra o que o terminal realmente exibe.
            let target = Self.target(in: route)
            let lines = DispatchQueue.main.sync { Dispatcher.shared.session(target)?.peek() }
            if let lines {
                respond(fd, status: "200 OK", json: ["target": target, "lines": lines])
            } else {
                respond(fd, status: "404 Not Found",
                        json: ["ok": false, "error": "alvo desconhecido '\(target)'"])
            }

        case ("GET", _, _) where route.contains("/activate"):
            // /activate?target=<workspace> — troca a aba ativa.
            let name = Self.target(in: route)
            let ok = DispatchQueue.main.sync { AppControl.activateSession?(name) ?? false }
            respond(fd, status: ok ? "200 OK" : "404 Not Found",
                    json: ["ok": ok, "workspace": name,
                           "known": DispatchQueue.main.sync { AppControl.sessionNames?() ?? [] }])

        case ("GET", _, _) where route.contains("/worktree"):
            // /worktree?target=ws[/id]&branch=X — worktree da sessão ou de um
            // terminal só, sem passar pelo diálogo.
            let query = Self.query(in: route)
            let payload = DispatchQueue.main.sync {
                AppControl.makeWorktree?(query["target"] ?? "", query["branch"] ?? "")
                    ?? ["ok": false, "error": "app sem worktree disponível"]
            }
            respond(fd, status: (payload["ok"] as? Bool) == true ? "200 OK" : "400 Bad Request",
                    json: payload)

        case ("GET", _, _) where route.contains("/layout"):
            // /layout?mode=canvas|mosaic — troca a visualização da sessão ativa.
            let mode = Self.query(in: route)["mode"] ?? ""
            let applied = DispatchQueue.main.sync { AppControl.setViewMode?(mode) }
            respond(fd, status: applied == nil ? "404 Not Found" : "200 OK",
                    json: ["ok": applied != nil, "mode": applied ?? mode])

        case ("GET", _, _) where route.contains("/open"):
            // /open?target=ws/id&folder=<path> — troca a pasta do editor.
            let query = Self.query(in: route)
            let target = query["target"] ?? ""
            let folder = query["folder"] ?? ""
            let ok = DispatchQueue.main.sync { () -> Bool in
                guard let node = EditorRegistry.node(target), !folder.isEmpty else { return false }
                node.open(folder: folder)
                return true
            }
            respond(fd, status: ok ? "200 OK" : "404 Not Found",
                    json: ["ok": ok, "target": target, "folder": folder])

        case ("GET", _, _) where route.contains("/view"):
            // /view?target=ws/id&name=Source%20Control — foca uma view do workbench.
            let query = Self.query(in: route)
            let target = query["target"] ?? ""
            let name = query["name"] ?? "Explorer"
            let result = awaitMain { done in
                guard let node = EditorRegistry.node(target) else {
                    done("erro: editor desconhecido '\(target)'")
                    return
                }
                node.focusView(named: name, completion: done)
            }
            respond(fd, status: "200 OK",
                    json: ["target": target, "view": name, "result": result ?? "timeout"])

        case ("GET", _, _) where route.contains("/file"):
            // /file?target=ws/id&name=<arquivo ou pasta> — clica no Explorer.
            let query = Self.query(in: route)
            let target = query["target"] ?? ""
            let name = query["name"] ?? ""
            let result = awaitMain { done in
                guard let node = EditorRegistry.node(target) else {
                    done("erro: editor desconhecido '\(target)'")
                    return
                }
                node.openInExplorer(named: name, completion: done)
            }
            respond(fd, status: "200 OK",
                    json: ["target": target, "name": name, "result": result ?? "timeout"])

        case ("GET", _, _) where route.contains("/change"):
            // /change?target=ws/id&index=0 — abre uma mudança no diff editor.
            let query = Self.query(in: route)
            let target = query["target"] ?? ""
            let index = Int(query["index"] ?? "0") ?? 0
            let result = awaitMain { done in
                guard let node = EditorRegistry.node(target) else {
                    done("erro: editor desconhecido '\(target)'")
                    return
                }
                node.openChange(index: index, matching: query["name"], completion: done)
            }
            respond(fd, status: "200 OK",
                    json: ["target": target, "index": index, "result": result ?? "timeout"])

        case ("GET", _, _) where route.contains("/probe"):
            // /probe?target=ws/id — sonda o DOM do workbench dentro do editor.
            let target = Self.target(in: route)
            let result = awaitMain { done in
                guard let node = EditorRegistry.node(target) else {
                    done("erro: editor desconhecido '\(target)'; conhecidos: "
                         + EditorRegistry.addresses.joined(separator: ", "))
                    return
                }
                node.probe(done)
            }
            respond(fd, status: "200 OK", json: ["target": target, "probe": result ?? "timeout"])

        case ("GET", _, _) where route.contains("/shot"):
            // /shot?target=ws/id — PNG do editor em disco. Log e DOM podem
            // mentir sobre "apareceu"; imagem não.
            let target = Self.target(in: route)
            let file = URL(fileURLWithPath: NSString(string: Flavor.current.config("shots").path)
                .expandingTildeInPath)
                .appendingPathComponent(target.replacingOccurrences(of: "/", with: "_") + ".png")
            let result = awaitMain(timeout: 20) { done in
                guard let node = EditorRegistry.node(target) else {
                    done("erro: editor desconhecido '\(target)'")
                    return
                }
                node.snapshot(to: file, completion: done)
            }
            respond(fd, status: "200 OK", json: ["target": target, "path": result ?? "timeout"])

        case ("POST", _, true):
            guard let request = try? JSONDecoder().decode(DispatchRequest.self, from: body) else {
                respond(fd, status: "400 Bad Request",
                        json: ["ok": false, "error": "json inválido"])
                return
            }
            deliver(request, to: fd)

        default:
            respond(fd, status: "404 Not Found",
                    json: ["ok": false, "error": "use GET /targets, POST /dispatch, POST /message ou POST /session"])
        }
    }

    private func deliver(_ request: DispatchRequest, to fd: Int32) {
        do {
            // Quem chamou sai do kernel, não do pedido: é o `fd` que identifica
            // o processo do outro lado, e por ele o terminal de origem.
            let result = try DispatchQueue.main.sync {
                let origin = Dispatcher.shared.session(callingOn: fd)
                return try Dispatcher.shared.dispatch(request, from: origin)
            }
            respond(fd, status: "200 OK", json: ["ok": true, "detail": result])
        } catch let error as Dispatcher.DispatchError {
            respond(fd, status: "404 Not Found", json: ["ok": false, "error": error.description])
        } catch {
            respond(fd, status: "400 Bad Request", json: ["ok": false, "error": "\(error)"])
        }
    }

    private static func query(in route: String) -> [String: String] {
        guard let raw = route.split(separator: "?").dropFirst().first else { return [:] }
        var out: [String: String] = [:]
        for pair in raw.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0])
            let value = String(parts[1])
            out[key] = value.removingPercentEncoding ?? value
        }
        return out
    }

    private static func target(in route: String) -> String { query(in: route)["target"] ?? "" }

    /// Roda uma operação assíncrona da main thread e espera o resultado.
    /// Screenshot e sonda de DOM são callbacks do WebKit, que só existem na
    /// main; o handler do socket vive numa fila de trabalho.
    private func awaitMain(timeout: TimeInterval = 10,
                           _ work: @escaping (@escaping (String) -> Void) -> Void) -> String? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: String?
        DispatchQueue.main.async {
            work { value in
                result = value
                semaphore.signal()
            }
        }
        return semaphore.wait(timeout: .now() + timeout) == .success ? result : nil
    }

    /// Lê cabeçalho até a linha em branco, depois exatamente Content-Length bytes.
    private func readRequest(_ fd: Int32) -> (head: String, body: Data)? {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        var headerEnd: Range<Data.Index>?

        while headerEnd == nil {
            let n = read(fd, &chunk, chunk.count)
            guard n > 0 else { return nil }
            buffer.append(contentsOf: chunk[0..<n])
            headerEnd = buffer.range(of: Data("\r\n\r\n".utf8))
            if buffer.count > 1 << 20 { return nil }
        }

        guard let separator = headerEnd,
              let head = String(data: buffer[..<separator.lowerBound], encoding: .utf8)
        else { return nil }

        var body = buffer[separator.upperBound...]
        let length = contentLength(in: head) ?? body.count

        while body.count < length {
            let n = read(fd, &chunk, chunk.count)
            guard n > 0 else { break }
            body.append(contentsOf: chunk[0..<n])
        }
        return (head, Data(body.prefix(length)))
    }

    private func contentLength(in head: String) -> Int? {
        for line in head.split(separator: "\r\n") where line.lowercased().hasPrefix("content-length:") {
            return Int(line.split(separator: ":")[1].trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    private func respond(_ fd: Int32, status: String, json: Any) {
        let body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
        let header = "HTTP/1.1 \(status)\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Connection: close\r\n\r\n"

        var response = Data(header.utf8)
        response.append(body)

        response.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var sent = 0
            while sent < raw.count {
                let n = write(fd, base.advanced(by: sent), raw.count - sent)
                if n <= 0 { return }
                sent += n
            }
        }
    }
}
