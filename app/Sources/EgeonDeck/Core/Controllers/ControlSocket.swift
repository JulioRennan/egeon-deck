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
    /// Fila só do watchdog. Não pode ser a do `accept`, que fica bloqueada dentro do
    /// `accept()` a vida inteira — timer agendado ali nunca dispara.
    private let watchQueue = DispatchQueue(label: "\(Flavor.current.identifier).control.watch",
                                           qos: .utility)

    /// Inode do arquivo depois do bind. É por ele que se sabe se o `sock` que está
    /// no disco ainda é o NOSSO — e é o que impede este processo de apagar o socket
    /// de outra instância na saída.
    private var boundInode: (dev: Int32, ino: UInt64)?

    /// Relógio que confere se o arquivo continua lá. Ver `watch()`.
    private var watchdog: DispatchSourceTimer?

    func start() {
        try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: Self.path).deletingLastPathComponent(),
            withIntermediateDirectories: true)

        guard Self.path.utf8.count < 104 else {
            Log.write("socket: caminho longo demais para sockaddr_un (\(Self.path))")
            return
        }

        // Duas instâncias do MESMO flavor: a segunda a subir apagava o `sock` da
        // primeira e botava o dela no lugar. Quando ela saía, o `unlink` do encerramento
        // levava o arquivo — e a primeira, viva, ficava com um socket que ninguém
        // alcança. Nada na tela dizia isso: o app parecia inteiro e só os ganchos do
        // CLI morriam, então nenhum agente avisava mais que tinha terminado.
        if let owner = Self.listenerPID() {
            Log.write("socket: JÁ TEM outra instância deste flavor (pid \(owner)) escutando em "
                      + "\(Self.path) — este processo segue sem socket de controle. "
                      + "Feche uma das duas: elas também disputam o \(Flavor.current.config("workbenches.json").lastPathComponent).")
            return
        }
        // Ninguém atende: o que estiver no caminho é resto de execução anterior.
        unlink(Self.path)

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

        // Sem CLOEXEC o fd de escuta vaza para todo processo filho — e os filhos aqui
        // são os pty dos agentes, que vivem horas. Um `lsof` mostrava cinco `claude`
        // segurando o socket do app.
        _ = fcntl(listenFD, F_SETFD, FD_CLOEXEC)
        boundInode = Self.inode(of: Self.path)

        Log.write("socket: escutando em \(Self.path)")
        acceptQueue.async { [weak self] in self?.acceptLoop() }
        watch()
    }

    func stop() {
        watchdog?.cancel()
        watchdog = nil
        if listenFD >= 0 { close(listenFD) }
        // Só apaga o que é nosso: o arquivo no caminho pode ser o socket de outra
        // instância, e apagá-lo deixaria ELA viva e inalcançável.
        if let mine = boundInode, let now = Self.inode(of: Self.path),
           now == mine { unlink(Self.path) }
        listenFD = -1
        boundInode = nil
    }

    /// Confere de dez em dez segundos se o arquivo do socket ainda é o nosso, e
    /// reconstrói quando não é.
    ///
    /// O modo de falhar aqui é silencioso e caro: quem perde o caminho continua com
    /// janela, canvas e agentes de pé, e só o relato do CLI para de chegar — o verde
    /// de "terminou" e o laranja de "precisa de você" simplesmente nunca mais
    /// aparecem, sem nenhuma linha de erro. Dez segundos porque é `stat` num arquivo.
    private func watch() {
        watchdog?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: watchQueue)
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler { [weak self] in
            guard let self, let mine = self.boundInode else { return }
            if let now = Self.inode(of: Self.path), now == mine { return }
            Log.write("socket: o arquivo \(Self.path) sumiu ou virou de outro processo — "
                      + "religando (sem isso os ganchos do CLI param de chegar em silêncio)")
            self.stop()
            self.start()
        }
        timer.resume()
        watchdog = timer
    }

    /// O pid de quem aceita conexão neste caminho agora, ou `nil` se ninguém aceita.
    /// Zero quando alguém atende mas o pid não veio.
    ///
    /// Conectar e não escrever nada: é o único teste que separa "instância viva" de
    /// "arquivo de socket órfão", e o órfão é o caso comum depois de um crash.
    ///
    /// O pid sai do próprio socket (`LOCAL_PEERPID`), e não de varrer a lista de
    /// processos: bundle em quarentena o macOS executa de uma cópia em
    /// `AppTranslocation`, e ali o caminho do processo não é nenhum dos que este
    /// código — ou o `install.sh` — conhece. É o que permite ao arranque dizer QUAL
    /// processo já está de pé em vez de só "tem alguém".
    static func listenerPID(at path: String = ControlSocket.path) -> pid_t? {
        var isSocket = stat()
        guard stat(path, &isSocket) == 0 else { return nil }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { tuple in
            tuple.withMemoryRebound(to: CChar.self, capacity: 104) { dest in
                _ = strcpy(dest, path)
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) { raw in
            raw.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, size) == 0 }
        }
        guard connected else { return nil }
        return Peer.pid(of: fd) ?? 0
    }

    private static func inode(of path: String) -> (dev: Int32, ino: UInt64)? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return (info.st_dev, info.st_ino)
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
            // bancada continuar podendo.
            let folder = Self.query(in: route)["folder"] ?? ""
            let payload = DispatchQueue.main.sync { () -> [String: Any] in
                let all = Dispatcher.shared.activeAddresses
                guard !folder.isEmpty else { return ["targets": all, "all": all] }
                let workbench = AppControl.workbenchOwning?(folder) ?? ""
                return ["targets": workbench.isEmpty
                            ? [] : all.filter { $0.hasPrefix(workbench + "/") },
                        "all": all,
                        "workbench": workbench,
                        // `session` é o nome antigo da chave. Fica por uma versão: a
                        // extensão instalada no code-server lê ela, e trocar as duas
                        // pontas no mesmo commit não atualiza quem já está rodando.
                        "session": workbench]
            }
            respond(fd, status: "200 OK", json: payload)

        case ("POST", _, _) where route.contains("/conversation") || route.contains("/session"):
            // /conversation?target=bancada/id&id=<uuid>[&transcript=<path>] — o CLI
            // relatando qual conversa está aberta. Chamava-se `/session`, que continua
            // aceito: o gancho vive em disco e um agente já rodando pode postar no
            // nome antigo antes de o app regravá-lo.
            // relatando qual conversa está aberta e onde a está gravando. Vem do
            // gancho `UserPromptSubmit`, a cada prompt.
            //
            // O transcript alimenta quem quiser ler a conversa como dados
            // (ADR-029) — o modo chat, quando voltar. Opcional porque um CLI
            // que não o informe continua valendo como agente — perde o thread, não
            // o dispatch.
            let query = Self.query(in: route)
            let id = query["id"] ?? ""
            guard !id.isEmpty else {
                respond(fd, status: "400 Bad Request", json: ["ok": false, "error": "id é obrigatório"])
                return
            }
            let resolved: Bool = DispatchQueue.main.sync {
                guard let target = hookCaller(fd, query: query) else { return false }
                AppControl.recordConversation?(target.address, id, query["transcript"])
                // Relatar a conversa também prova que o gancho chega aqui — e é
                // isso que faz o terminal parar de depender de adivinhação sobre
                // a tela já no primeiro turno (ADR-024).
                target.hookReported(.prompt)
                return true
            }
            if resolved {
                respond(fd, status: "200 OK", json: ["ok": true])
            } else {
                respond(fd, status: "403 Forbidden", json: ["ok": false, "error": Self.notFromTerminal])
            }

        case ("POST", _, _) where route.contains("/activity"):
            // /activity?target=bancada/id&event=stop|ask[&transcript=path] — o CLI relatando que o
            // turno acabou (gancho `Stop`) ou que está pedindo permissão (gancho
            // `Notification`). São os dois únicos avisos que chamam você, e vêm
            // do programa em vez de saírem de heurística sobre o pty (ADR-024).
            let query = Self.query(in: route)
            guard let raw = query["event"], !raw.isEmpty else {
                respond(fd, status: "400 Bad Request", json: ["ok": false, "error": "event é obrigatório"])
                return
            }
            guard let event = HookEvent(rawValue: raw) else {
                respond(fd, status: "400 Bad Request",
                        json: ["ok": false,
                               "error": "evento desconhecido '\(raw)'; use \(HookEvent.expected)"])
                return
            }
            let transcript = query["transcript"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            let resolved: Bool = DispatchQueue.main.sync {
                guard let target = hookCaller(fd, query: query) else { return false }
                target.hookReported(event, transcript: transcript)
                return true
            }
            if resolved {
                respond(fd, status: "200 OK", json: ["ok": true])
            } else {
                respond(fd, status: "403 Forbidden", json: ["ok": false, "error": Self.notFromTerminal])
            }

        case ("POST", _, _) where route.contains("/message"):
            // /message?from=<id>&target=<bancada/id> — corpo é o texto puro.
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

        case (_, _, _) where bare.hasPrefix("/maestro/"):
            // /maestro/bench · /maestro/models · POST /maestro/apply[?dry=1] —
            // o terminal maestro lendo e montando a bancada (ADR-066). Quem
            // pergunta sai do processo do outro lado, como no `egeon send`: o
            // controller recusa quem não é maestro.
            let dry = Self.query(in: route)["dry"] == "1"
            let reply = DispatchQueue.main.sync { () -> (status: Int, json: [String: Any]) in
                guard let maestro = AppControl.maestro else { return (503, ["ok": false, "error": "app sem bancadas"]) }
                let caller = Dispatcher.shared.target(callingOn: fd)?.address
                switch (method, bare.hasSuffix("/bench"), bare.hasSuffix("/models"), bare.hasSuffix("/apply")) {
                case ("GET", true, _, _): return maestro.bench(caller: caller)
                case ("GET", _, true, _): return maestro.models(caller: caller)
                case ("POST", _, _, true): return maestro.apply(body, caller: caller, dry: dry)
                default:
                    return (404, ["ok": false, "error": "use GET /maestro/bench, GET /maestro/models "
                                                        + "ou POST /maestro/apply[?dry=1]"])
                }
            }
            respond(fd, status: Self.statusLine(reply.status), json: reply.json)

        case ("GET", _, _) where bare == "/maestro":
            // /maestro?target=<bancada/nó>&on=1|0 — liga o maestro de fora, como
            // o checkbox do formulário. Só de fora: de dentro de um terminal
            // seria um agente se promovendo (ADR-066).
            let query = Self.query(in: route)
            let outcome = DispatchQueue.main.sync { () -> String? in
                guard Dispatcher.shared.target(callingOn: fd) == nil else {
                    return "só o usuário liga o maestro — de dentro de um terminal, não"
                }
                // Nil de volta é sucesso: `?? erro` aqui o transformaria em falha.
                guard let setMaestro = AppControl.setMaestro else { return "app sem bancadas" }
                return setMaestro(query["target"] ?? "", query["on"] != "0")
            }
            if let outcome {
                respond(fd, status: "400 Bad Request", json: ["ok": false, "error": outcome])
            } else {
                respond(fd, status: "200 OK", json: ["ok": true, "target": query["target"] ?? "",
                                                     "maestro": query["on"] != "0"])
            }

        case ("POST", _, _) where route.contains("/trace"):
            // /trace — corpo é o texto puro (`egeon trace`, heredoc). Quem
            // escreveu sai do processo do outro lado do socket, e CLI, modelo e
            // conversa saem do nó: o agente não carimba nada (ADR-036).
            let text = String(decoding: body, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let outcome = DispatchQueue.main.sync { () -> (status: String, json: [String: Any]) in
                guard let origin = Dispatcher.shared.target(callingOn: fd) else {
                    return ("403 Forbidden", ["ok": false, "error": "esta conexão não veio de um terminal"])
                }
                guard !text.isEmpty else {
                    return ("400 Bad Request", ["ok": false, "error": "texto vazio — o que você fez?"])
                }
                guard let identity = AppControl.nodeIdentity?(origin.address) else {
                    return ("404 Not Found", ["ok": false, "error": "nó sem bancada carregada"])
                }
                let entry = TraceEntry(address: origin.address, workbenchID: identity.workbenchID,
                                       at: Date(), cli: identity.cli, model: identity.model,
                                       conversation: identity.conversation, text: text)
                TraceLog.shared.record(entry)
                return ("200 OK", ["ok": true, "address": origin.address,
                                   "file": TraceLog.shared.file(for: entry).path])
            }
            respond(fd, status: outcome.status, json: outcome.json)

        case ("POST", _, _) where route.contains("/workbench/clear"):
            // /workbench/clear?target=<bancada> — o botão de limpar, sem o
            // diálogo: `/clear` em todo agente e a conversa arquivada (ADR-037).
            // A resposta só sai no fim: limpar é mandar o `clear`, ESPERAR os
            // agentes assentarem e só então arquivar (ADR-059) — responder no
            // disparo devolvia "ok" antes de a conversa ter saído do lugar, e
            // quem confere pelo socket via o estado do meio.
            let target = Self.query(in: route)["target"] ?? ""
            let done = DispatchSemaphore(value: 0)
            var payload: [String: Any] = ["ok": false, "error": "app sem canvas"]
            DispatchQueue.main.async {
                guard let clear = AppControl.clearWorkbench else { done.signal(); return }
                clear(target) { result in
                    payload = result
                    done.signal()
                }
            }
            // Teto acima do do próprio cleaner: aqui só se protege a conexão
            // de ficar pendurada se o app nunca responder.
            if done.wait(timeout: .now() + 90) == .timedOut {
                payload = ["ok": false, "error": "limpeza não respondeu em 90s"]
            }
            respond(fd, status: payload["ok"] as? Bool == true ? "200 OK" : "404 Not Found",
                    json: payload)

        case ("POST", _, _) where route.contains("/chat/clear"):
            // /chat/clear?target=<bancada> — arquiva a conversa corrente do chat
            // (`chat.jsonl` → `chat-archive/`) e começa outra. Nada é apagado
            // (ADR-037).
            let target = Self.query(in: route)["target"] ?? ""
            let payload = DispatchQueue.main.sync {
                AppControl.clearChat?(target) ?? ["ok": false, "error": "app sem canvas"]
            }
            respond(fd, status: payload["ok"] as? Bool == true ? "200 OK" : "404 Not Found",
                    json: payload)

        case ("GET", _, _) where route.contains("/move"):
            // /move?kind=workspace|project|workbench|store|unstore|drawer
            //      &id=<id>&to=<n>[&parent=<id>]
            // — reposiciona na árvore. Arrastar não é dirigível de fora sem
            // Acessibilidade (ADR-003), e esta é a mesma operação.
            let query = Self.query(in: route)
            let payload = DispatchQueue.main.sync {
                AppControl.moveInTree?(query["kind"] ?? "", query["id"] ?? "",
                                       query["parent"] ?? "", Int(query["to"] ?? "") ?? 0)
            }
            let ok = payload?["ok"] as? Bool ?? false
            respond(fd, status: ok ? "200 OK" : "400 Bad Request",
                    json: payload ?? ["ok": false, "error": "app sem árvore"])

        case ("GET", _, _) where route.contains("/tabs"):
            // /tabs[?close=<bancada>][?move=<bancada>&to=<n>] — as bancadas
            // abertas, na ordem da faixa, com os badges; `close` fecha a aba sem
            // encerrar a bancada e `move` reordena, como o arrasto.
            let query = Self.query(in: route)
            let fechar = query["close"] ?? ""
            let mover = query["move"] ?? ""
            let payload = DispatchQueue.main.sync { () -> [String: Any] in
                if !mover.isEmpty, let move = AppControl.moveTab {
                    var out = move(mover, Int(query["to"] ?? "") ?? -1)
                    out.merge(AppControl.tabsSnapshot?() ?? [:]) { a, _ in a }
                    return out
                }
                if !fechar.isEmpty, let close = AppControl.closeTab {
                    var out = close(fechar)
                    out.merge(AppControl.tabsSnapshot?() ?? [:]) { a, _ in a }
                    return out
                }
                return AppControl.tabsSnapshot?() ?? [:]
            }
            respond(fd, status: payload["ok"] as? Bool == false ? "404 Not Found" : "200 OK",
                    json: payload)

        case ("GET", _, _) where route.contains("/workspaces"):
            // /workspaces — a árvore da barra lateral (ADR-043), para conferir
            // conciliação e pertencimento sem abrir a barra.
            let payload = DispatchQueue.main.sync { AppControl.workspacesSnapshot?() ?? [:] }
            respond(fd, status: "200 OK", json: payload)

        case ("GET", _, _) where route.contains("/peers"):
            // /peers — quem QUEM PERGUNTA pode acionar. Sem parâmetro de
            // identidade: o remetente sai do processo do outro lado do socket.
            let peers = DispatchQueue.main.sync { () -> [[String: Any]] in
                guard let origin = Dispatcher.shared.target(callingOn: fd) else { return [] }
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
                guard let origin = Dispatcher.shared.target(callingOn: fd) else {
                    return ["detail": "esta conexão não veio de um terminal"]
                }
                // Quem VOCÊ é vem antes de como você está: o agente não sabe
                // o próprio papel nem o próprio endereço, e sem isso ele não
                // tem como escolher entre delegar e fazer (ADR-054).
                var payload: [String: Any] = [
                    "address": origin.address,
                    "pending": origin.pending,
                    "peers": Dispatcher.shared.peers(of: origin.address).count]
                if let role = AppControl.nodeRole?(origin.address) { payload["role"] = role }
                if AppControl.nodeIsMaestro?(origin.address) == true { payload["maestro"] = true }
                if let identity = AppControl.nodeIdentity?(origin.address) {
                    payload["cli"] = identity.cli
                    payload["model"] = identity.model
                }
                payload["workbench"] = String(origin.address.split(separator: "/").first ?? "")
                return payload
            }
            respond(fd, status: "200 OK", json: payload)

        case ("GET", _, _) where route.contains("/geometry"):
            // /geometry — onde cada nó está na tela, para dirigir gestos de fora.
            let payload = DispatchQueue.main.sync { AppControl.canvasGeometry?() ?? [:] }
            respond(fd, status: "200 OK", json: payload)

        case ("POST", _, _) where route.contains("/compose"):
            // /compose?target=ws[&send=1] — corpo em texto puro vai para a caixa
            // do chat; `send=1` aperta o Enter. Texto puro e não JSON porque o
            // que interessa aqui é justamente prompt de VÁRIAS linhas.
            let query = Self.query(in: route)
            let target = query["target"] ?? ""
            let text = String(decoding: body, as: UTF8.self)
            let result = DispatchQueue.main.sync {
                AppControl.chatCompose?(target, text, query["send"] == "1") ?? nil
            }
            respond(fd, status: result == nil ? "404 Not Found" : "200 OK",
                    json: result ?? ["ok": false,
                                     "error": "bancada sem chat montado '\(target)'"])

        case ("GET", _, _) where route.contains("/chat"):
            // /chat?target=ws[&scroll=top|bottom][&focus=id][&expand=bloco] — o
            // modo chat da bancada, como dados; `scroll` rola a thread, `focus`
            // escolhe o participante antes de responder e `expand` abre ou
            // recolhe um passo pelo id que o retrato lista em `blocks`.
            let query = Self.query(in: route)
            let target = query["target"] ?? ""
            let payload = DispatchQueue.main.sync {
                if let id = query["focus"] { AppControl.chatFocus?(target, id) }
                if let id = query["expand"] { AppControl.chatExpandStep?(target, id) }
                if let edge = query["scroll"] { AppControl.chatScroll?(target, edge) }
                return AppControl.chatState?(target) ?? nil
            }
            respond(fd, status: payload == nil ? "404 Not Found" : "200 OK",
                    json: payload ?? ["ok": false, "error": "bancada desconhecida '\(target)'"])

        case ("GET", _, _) where route.contains("/peek"):
            // /peek?target=ws/id[&lines=n] — mostra o que o terminal realmente
            // exibe. De dentro de um terminal (`egeon peek`), só de vizinho.
            let target = Self.target(in: route)
            let count = Self.query(in: route)["lines"].flatMap(Int.init) ?? 20
            enum Peek { case lines([String]), forbidden, unknown }
            let result = DispatchQueue.main.sync { () -> Peek in
                let origin = Dispatcher.shared.target(callingOn: fd)?.address
                let peers = origin.map { Dispatcher.shared.peers(of: $0).map(\.address) } ?? []
                guard Dispatcher.mayPeek(target, from: origin, peers: peers) else { return .forbidden }
                guard let node = Dispatcher.shared.target(target) else { return .unknown }
                return .lines(node.peek(lines: max(1, min(count, 200))))
            }
            switch result {
            case .lines(let lines):
                respond(fd, status: "200 OK", json: ["target": target, "lines": lines])
            case .forbidden:
                respond(fd, status: "403 Forbidden",
                        json: ["ok": false,
                               "error": "não existe ligação de você para '\(target)' — "
                                   + "desenhe a aresta no canvas"])
            case .unknown:
                respond(fd, status: "404 Not Found",
                        json: ["ok": false, "error": "alvo desconhecido '\(target)'"])
            }

        case ("GET", _, _) where route.contains("/activate"):
            // /activate?target=<workspace> — troca a aba ativa.
            let name = Self.target(in: route)
            let ok = DispatchQueue.main.sync { AppControl.activateWorkbench?(name) ?? false }
            respond(fd, status: ok ? "200 OK" : "404 Not Found",
                    json: ["ok": ok, "workspace": name,
                           "known": DispatchQueue.main.sync { AppControl.workbenchNames?() ?? [] }])

        case ("GET", _, _) where route.contains("/worktree"):
            // /worktree?target=ws[/id]&branch=X — worktree da bancada ou de um
            // terminal só, sem passar pelo diálogo.
            //
            // `&nodes=back:fix/api,sub:spike` customiza a branch de terminais
            // específicos, que é o que as linhas do formulário fazem. Sem isso não
            // havia como verificar esse caminho de fora: as linhas moram num
            // `NSAlert`.
            let query = Self.query(in: route)
            var nodeBranches: [String: String] = [:]
            for par in (query["nodes"] ?? "").split(separator: ",") {
                let campos = par.split(separator: ":", maxSplits: 1).map(String.init)
                guard let id = campos.first, !id.isEmpty else { continue }
                nodeBranches[id] = campos.count == 2 ? campos[1] : ""
            }
            let payload = DispatchQueue.main.sync {
                AppControl.makeWorktree?(query["target"] ?? "", query["branch"] ?? "",
                                         nodeBranches)
                    ?? ["ok": false, "error": "app sem worktree disponível"]
            }
            respond(fd, status: (payload["ok"] as? Bool) == true ? "200 OK" : "400 Bad Request",
                    json: payload)

        case ("GET", _, _) where route.contains("/edge"):
            // /edge?target=ws&from=a&to=b[&direction=->|<-|<->|cycle|none] — cria a
            // ligação ou troca a direção dela. Sem `direction`, cria como o arrasto
            // cria, com o padrão da casa; `cycle` é exatamente o botão da linha.
            let query = Self.query(in: route)
            let payload = DispatchQueue.main.sync {
                AppControl.setEdgeDirection?(query["target"] ?? "", query["from"] ?? "",
                                             query["to"] ?? "", query["direction"] ?? "")
                    ?? ["ok": false, "error": "app sem arestas disponíveis"]
            }
            respond(fd, status: (payload["ok"] as? Bool) == true ? "200 OK" : "400 Bad Request",
                    json: payload)

        case ("GET", _, _) where route.contains("/mosaic"):
            // /mosaic?target=ws&swap=id1,id2 — troca dois cards de painel, o mesmo
            // que arrastar o cabeçalho de um sobre o outro.
            let query = Self.query(in: route)
            let pares = (query["swap"] ?? "").split(separator: ",").map(String.init)
            guard pares.count == 2 else {
                respond(fd, status: "400 Bad Request",
                        json: ["ok": false, "error": "use swap=id1,id2"])
                return
            }
            let payload = DispatchQueue.main.sync {
                AppControl.swapMosaic?(query["target"] ?? "", pares[0], pares[1])
                    ?? ["ok": false, "error": "app sem mosaico disponível"]
            }
            respond(fd, status: (payload["ok"] as? Bool) == true ? "200 OK" : "400 Bad Request",
                    json: payload)

        case ("GET", _, _) where route.contains("/remove"):
            // /remove?target=ws[&worktrees=1] — remove a bancada, e só com
            // `worktrees=1` apaga as worktrees dela do disco. O padrão é não
            // apagar: é `worktree remove --force` do outro lado.
            // A resposta sai no fim, mas a main não espera junto: o `worktree
            // remove` roda na fila de fundo do app, e só esta conexão fica parada.
            let query = Self.query(in: route)
            let done = DispatchSemaphore(value: 0)
            var payload: [String: Any] = ["ok": false, "error": "app sem remoção disponível"]
            DispatchQueue.main.async {
                guard let remove = AppControl.removeWorkbench else { done.signal(); return }
                remove(query["target"] ?? "", query["worktrees"] == "1") { result in
                    payload = result
                    done.signal()
                }
            }
            if done.wait(timeout: .now() + 600) == .timedOut {
                payload = ["ok": false, "error": "remoção não respondeu em 10min"]
            }
            respond(fd, status: (payload["ok"] as? Bool) == true ? "200 OK" : "400 Bad Request",
                    json: payload)

        case ("GET", _, _) where route.contains("/model"):
            // /model?target=ws/id[&model=nome] — o mesmo que escolher no seletor do
            // cabeçalho: reinicia o terminal com o modelo, mantendo a conversa.
            // Sem `model`, volta ao padrão do CLI. Com `effort=nível` troca o
            // esforço em vez do modelo; `effort=default` volta ao padrão — vazio
            // não serve, `effort=` nem chega ao mapa da query. `ultracode=on|off`
            // liga e desliga o ultracode.
            let query = Self.query(in: route)
            let target = query["target"] ?? ""
            let choice: ModelChoice
            let field: String
            if let ultracode = query["ultracode"] {
                choice = .ultracode(ultracode == "on" || ultracode == "1" || ultracode == "true")
                field = "ultracode"
            } else if let effort = query["effort"] {
                choice = .effort(effort == "default" ? nil : effort)
                field = "effort"
            } else {
                choice = .model(query["model"].flatMap { $0.isEmpty ? nil : $0 })
                field = "model"
            }
            let error: String? = DispatchQueue.main.sync {
                guard let handler = AppControl.setNodeModel else { return "app sem canvas" }
                return handler(target, choice)
            }
            if let error {
                respond(fd, status: "404 Not Found", json: ["ok": false, "error": error])
            } else {
                let value: String?
                switch choice {
                case .model(let model): value = model
                case .effort(let effort): value = effort
                case .ultracode(let on): value = on ? "on" : "off"
                }
                respond(fd, status: "200 OK", json: ["ok": true, "target": target, field: value ?? "padrão"])
            }

        case ("GET", _, _) where route.contains("/layout"):
            // /layout?mode=canvas|mosaic — troca a visualização da bancada ativa.
            let mode = Self.query(in: route)["mode"] ?? ""
            let applied = DispatchQueue.main.sync { AppControl.setViewMode?(mode) }
            respond(fd, status: applied == nil ? "404 Not Found" : "200 OK",
                    json: ["ok": applied != nil, "mode": applied ?? mode])

        case ("GET", _, _) where route.contains("/sidebar"):
            // /sidebar?collapsed=0|1|toggle — recolhe a barra de bancadas, abre,
            // ou alterna.
            //
            // `toggle` existe para cobrir exatamente o que o ⌘/ e o botão da barra
            // fazem: nem a tecla de menu nem o clique são dirigíveis de fora sem
            // permissão de Acessibilidade (ADR-003).
            let raw = Self.query(in: route)["collapsed"] ?? ""
            let state = DispatchQueue.main.sync { () -> Bool? in
                raw == "toggle" ? AppControl.toggleSidebar?()
                                : AppControl.collapseSidebar?(raw == "1")
            }
            respond(fd, status: state == nil ? "404 Not Found" : "200 OK",
                    json: ["ok": state != nil, "collapsed": state ?? false])

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
            // /shot?target=ws/id — PNG em disco. Log e DOM podem mentir sobre
            // "apareceu"; imagem não.
            //
            // `&card=1` fotografa o CARD inteiro, com cabeçalho e borda, em vez do
            // conteúdo do editor — é a única forma de conferir de fora uma mudança
            // que é só desenho, como o cabeçalho de duas linhas.
            let query = Self.query(in: route)
            let target = query["target"] ?? ""
            let file = URL(fileURLWithPath: NSString(string: Flavor.current.config("shots").path)
                .expandingTildeInPath)
                .appendingPathComponent(target.replacingOccurrences(of: "/", with: "_") + ".png")
            let card = query["card"] == "1" || EditorRegistry.node(target) == nil
            let result: String?
            if card {
                result = DispatchQueue.main.sync {
                    AppControl.cardSnapshot?(target, file) ?? "erro: app sem canvas"
                }
            } else {
                result = awaitMain(timeout: 20) { done in
                    guard let node = EditorRegistry.node(target) else {
                        done("erro: editor desconhecido '\(target)'")
                        return
                    }
                    node.snapshot(to: file, completion: done)
                }
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
                    json: ["ok": false, "error": "use GET /targets, POST /dispatch, POST /message ou POST /conversation"])
        }
    }

    static let notFromTerminal = "esta conexão não veio de um terminal"

    /// Quem é o terminal por trás de um gancho: pelo processo que abriu a
    /// conexão, como o `egeon` (ADR-040). O `curl` do gancho é bisneto do
    /// shell do pty (`zsh` → `claude` → `sh -c` → `bash` → `curl`), e a
    /// ascendência chega lá. `target` na query só como reserva — um `curl` seu
    /// ou um script antigo ainda em disco — e avisado no log, porque é o
    /// caminho que o nome da bancada com espaço quebrava. Chamar na main.
    private func hookCaller(_ fd: Int32, query: [String: String]) -> Target? {
        if let target = Dispatcher.shared.target(callingOn: fd) { return target }
        guard let named = query["target"], !named.isEmpty,
              let target = Dispatcher.shared.target(named) else { return nil }
        Log.write("gancho[\(named)]: pid não resolveu o terminal; usando target da query")
        return target
    }

    private func deliver(_ request: DispatchRequest, to fd: Int32) {
        do {
            // Quem chamou sai do kernel, não do pedido: é o `fd` que identifica
            // o processo do outro lado, e por ele o terminal de origem.
            let result = try DispatchQueue.main.sync {
                let origin = Dispatcher.shared.target(callingOn: fd)
                return try Dispatcher.shared.dispatch(request, from: origin)
            }
            respond(fd, status: "200 OK", json: ["ok": true, "detail": result])
        } catch let error as Dispatcher.DispatchError {
            respond(fd, status: "404 Not Found", json: ["ok": false, "error": error.description])
        } catch {
            respond(fd, status: "400 Bad Request", json: ["ok": false, "error": "\(error)"])
        }
    }

    /// Função de shell para os scripts que o app gera (`agent-hook.sh`,
    /// `egeon`): codifica um trecho de URL byte a byte. Existe porque o nome
    /// da bancada pode ter espaço e `+` ("SPEI + SPI"), e a linha HTTP é
    /// dividida no espaço: `target=SPEI + SPI/backend` chegava como `SPEI`,
    /// alvo desconhecido, e o gancho sumia sem log. `LC_ALL=C` para o loop
    /// andar por byte — um `ç` são dois bytes, e é assim que `%XX` os quer.
    /// Sem processo externo: o gancho roda a cada prompt e segura a TUI. Os
    /// dois últimos hex e não `%02X` direto: o bash 3.2 do macOS estende o
    /// sinal de byte ≥ 0x80 e imprime `FFFFFFFFFFFFFFC3`.
    static let shellEncoder = """
        enc() {
            local LC_ALL=C s="$1" out="" c h i
            for ((i = 0; i < ${#s}; i++)); do
                c="${s:i:1}"
                case "$c" in
                  [a-zA-Z0-9._~/-]) out+="$c" ;;
                  *) h=$(printf '%02X' "'$c"); out+="%${h: -2}" ;;
                esac
            done
            printf '%s' "$out"
        }
        """

    private static func statusLine(_ code: Int) -> String {
        switch code {
        case 200: return "200 OK"
        case 400: return "400 Bad Request"
        case 403: return "403 Forbidden"
        case 404: return "404 Not Found"
        case 422: return "422 Unprocessable Entity"
        default: return "\(code) Service Unavailable"
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
