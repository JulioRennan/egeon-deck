import Foundation

/// Quem está do outro lado do socket de controle, segundo o kernel.
///
/// Existe porque a alternativa — o remetente se identificar no pedido — não é
/// verificável: quem monta o `curl` é o agente, e ele pode escrever qualquer
/// endereço ali, ou omitir o campo e passar por você. Com as guardas de cadeia
/// penduradas nesse campo, mentir sobre ele é contorná-las todas.
///
/// O kernel sabe qual processo abriu a conexão e não aceita opinião a respeito.
enum Peer {

    /// Pid do processo do outro lado da conexão.
    static func pid(of fd: Int32) -> pid_t? {
        var pid: pid_t = 0
        var size = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) == 0, pid > 0 else {
            return nil
        }
        return pid
    }

    /// Sobe a cadeia de pais a partir de `pid` procurando um processo conhecido.
    ///
    /// Sobe, e não compara direto, porque quem abre a conexão nunca é o processo
    /// que o app lançou: o `egeon` é neto do `zsh` do terminal, e um agente que
    /// chame por um subshell está mais fundo ainda. O que identifica o terminal é
    /// a ancestralidade, não o processo imediato.
    ///
    /// O teto de saltos é rede contra uma cadeia de `ppid` em ciclo — não deve
    /// acontecer, e um laço infinito dentro do handler do socket travaria o app.
    static func owner(of pid: pid_t, known: (pid_t) -> Bool) -> pid_t? {
        var current = pid
        for _ in 0..<32 {
            if known(current) { return current }
            // pid 1 é o launchd: chegou na raiz sem achar dono.
            guard let parent = parent(of: current), parent > 1 else { return nil }
            current = parent
        }
        return nil
    }

    private static func parent(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}
