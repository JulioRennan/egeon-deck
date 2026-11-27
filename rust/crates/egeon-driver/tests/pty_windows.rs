//! Pty de verdade no Windows: processos reais num ConPTY. Nada aqui toca
//! `~/.egeon`. O par do `pty.rs` do unix, com `cmd.exe` e PowerShell no lugar
//! do `sh`.
//!
//! O ConPTY entrega a tela, não o fluxo cru: a saída vem com sequências de
//! controle (limpar, posicionar o cursor, título) em volta do texto. Por isso
//! os testes procuram o texto em vez de compará-lo inteiro.

#![cfg(windows)]
// Auxiliares e testes: falhar no `unwrap` reprova o teste que o chamou.
#![allow(clippy::unwrap_used, clippy::expect_used, clippy::panic)]

mod powershell_slots;

use std::path::PathBuf;
use std::sync::mpsc::{self, Receiver, RecvTimeoutError};
use std::thread;
use std::time::{Duration, Instant};

use egeon_core::ports::procs::{ProcessDetail, ProcessDriver};
use egeon_core::ports::pty::{
    PtyDriver, PtyError, PtyEvent, PtyExit, PtySession, PtySignal, PtySize, PtySpec,
};
use egeon_driver::{SystemProcs, SystemPty};

const SIZE: PtySize = PtySize { cols: 80, rows: 24 };
/// O PowerShell leva segundos para abrir na máquina do CI. Prazo maior não é
/// conserto: na ci/win-7 o que passou dele foi travamento, não demora.
const LIMIT: Duration = Duration::from_secs(30);

struct Child {
    session: Box<dyn PtySession>,
    events: Receiver<PtyEvent>,
    /// Desde o spawn: a falha diz quanto o filho levou, para separar demora
    /// de travamento.
    started: Instant,
    /// A vaga de PowerShell, quando o filho é um.
    _slot: Option<powershell_slots::Slot>,
}

fn system_root() -> PathBuf {
    std::env::var_os("SystemRoot").map_or_else(|| PathBuf::from(r"C:\Windows"), PathBuf::from)
}

fn base_env() -> Vec<(String, String)> {
    let root = system_root().display().to_string();
    vec![
        ("SystemRoot".into(), root.clone()),
        ("PATH".into(), format!(r"{root}\System32;{root}")),
        ("TERM".into(), "xterm-256color".into()),
    ]
}

fn cmd(command: &str) -> PtySpec {
    PtySpec {
        program: system_root().join("System32").join("cmd.exe"),
        args: vec!["/d".into(), "/c".into(), command.to_string()],
        env: base_env(),
        cwd: None,
        size: SIZE,
    }
}

/// O PowerShell do teste. Os scripts não chamam cmdlets de módulo
/// (`Write-Output`, `Start-Sleep`, `Start-Process`): carregar o módulo na
/// primeira chamada chegou a custar uns 15 s por sessão no runner do CI, e
/// é o PowerShell que demora, não o pty. A saída vai pela pipeline e o resto
/// pelo .NET.
fn powershell(script: &str) -> PtySpec {
    PtySpec {
        program: egeon_driver::environment::user_shell(),
        args: vec![
            "-NoLogo".into(),
            "-NoProfile".into(),
            "-NonInteractive".into(),
            "-Command".into(),
            script.to_string(),
        ],
        env: base_env(),
        cwd: None,
        size: SIZE,
    }
}

fn spawn(spec: PtySpec) -> Child {
    let slot =
        (spec.program == egeon_driver::environment::user_shell()).then(powershell_slots::slot);
    let started = Instant::now();
    let child = SystemPty.spawn(spec).unwrap();
    let (tx, events) = mpsc::channel();
    let mut source = child.events;
    thread::spawn(move || {
        while let Some(event) = source.blocking_recv() {
            if tx.send(event).is_err() {
                break;
            }
        }
    });
    Child {
        session: child.session,
        events,
        started,
        _slot: slot,
    }
}

impl Child {
    fn timed<T>(&self, result: Result<T, String>) -> Result<T, String> {
        result.map_err(|e| format!("{e} (após {:.1?} desde o spawn)", self.started.elapsed()))
    }

    fn read_until(&mut self, needle: &str) -> Result<String, String> {
        let result = self.read_until_raw(needle);
        self.timed(result)
    }

    fn read_number(&mut self, tag: &str) -> Result<u32, String> {
        let result = self.read_number_raw(tag);
        self.timed(result)
    }

    fn read_to_end(&mut self) -> Result<(String, PtyExit), String> {
        let result = self.read_to_end_raw();
        self.timed(result)
    }

    fn read_until_raw(&mut self, needle: &str) -> Result<String, String> {
        let deadline = Instant::now() + LIMIT;
        let mut seen = String::new();
        while !seen.contains(needle) {
            let left = deadline.saturating_duration_since(Instant::now());
            match self.events.recv_timeout(left) {
                Ok(PtyEvent::Output(bytes)) => seen.push_str(&String::from_utf8_lossy(&bytes)),
                Ok(PtyEvent::Exited(exit)) => {
                    return Err(format!(
                        "saiu ({exit:?}) sem {needle:?}; saída: {:?}",
                        tail(&seen)
                    ));
                }
                Err(RecvTimeoutError::Timeout) => {
                    return Err(format!("esperava {needle:?}; saída: {:?}", tail(&seen)));
                }
                Err(RecvTimeoutError::Disconnected) => {
                    return Err(format!(
                        "canal fechou sem {needle:?}; saída: {:?}",
                        tail(&seen)
                    ));
                }
            }
        }
        Ok(seen)
    }

    /// Lê até aparecer `tag<número>:` e devolve o número.
    fn read_number_raw(&mut self, tag: &str) -> Result<u32, String> {
        let deadline = Instant::now() + LIMIT;
        let mut seen = String::new();
        loop {
            if let Some(number) = number_after(&seen, tag) {
                return Ok(number);
            }
            let left = deadline.saturating_duration_since(Instant::now());
            match self.events.recv_timeout(left) {
                Ok(PtyEvent::Output(bytes)) => seen.push_str(&String::from_utf8_lossy(&bytes)),
                other => return Err(format!("sem {tag}: {other:?}; saída: {:?}", tail(&seen))),
            }
        }
    }

    /// Lê até o `Exited` e confere que ele é o último evento.
    fn read_to_end_raw(&mut self) -> Result<(String, PtyExit), String> {
        let deadline = Instant::now() + LIMIT;
        let mut seen = Vec::new();
        loop {
            let left = deadline.saturating_duration_since(Instant::now());
            match self.events.recv_timeout(left) {
                Ok(PtyEvent::Output(bytes)) => seen.extend(bytes),
                Ok(PtyEvent::Exited(exit)) => {
                    let text = String::from_utf8_lossy(&seen).into_owned();
                    return match self.events.recv_timeout(LIMIT) {
                        Err(RecvTimeoutError::Disconnected) => Ok((text, exit)),
                        other => Err(format!("havia evento depois do Exited: {other:?}")),
                    };
                }
                Err(RecvTimeoutError::Timeout) => {
                    return Err(format!(
                        "filho não terminou; saída: {:?}",
                        tail(&String::from_utf8_lossy(&seen))
                    ));
                }
                Err(RecvTimeoutError::Disconnected) => {
                    return Err("canal fechou sem Exited".to_string());
                }
            }
        }
    }
}

/// O fim da saída, para a mensagem de falha: a saída inteira de um teste
/// longo numa linha só derrubou o log do passo no CI (ci/win-7).
fn tail(text: &str) -> String {
    const KEEP: usize = 2000;
    let start = text.char_indices().rev().nth(KEEP).map_or(0, |(i, _)| i);
    if start == 0 {
        text.to_owned()
    } else {
        format!("…{}", &text[start..])
    }
}

fn alive(pid: u32) -> bool {
    SystemProcs
        .list(ProcessDetail::Tree)
        .map(|all| all.iter().any(|p| p.pid == pid))
        .unwrap_or(false)
}

fn wait_gone(pid: u32) -> bool {
    let deadline = Instant::now() + LIMIT;
    while Instant::now() < deadline {
        if !alive(pid) {
            return true;
        }
        thread::sleep(Duration::from_millis(100));
    }
    false
}

/// O número entre `tag` e o `:` seguinte na saída. Procura em todas as
/// ocorrências: o título da janela (OSC 0) pode trazer o texto do comando.
fn number_after(output: &str, tag: &str) -> Option<u32> {
    output.split(tag).skip(1).find_map(|rest| {
        let digits: String = rest.chars().take_while(char::is_ascii_digit).collect();
        if !rest[digits.len()..].starts_with(':') {
            return None;
        }
        digits.parse().ok()
    })
}

#[test]
fn echo_oi_devolve_oi() {
    let mut child = spawn(cmd("echo oi-do-cmd"));
    let (output, exit) = child.read_to_end().unwrap();

    assert!(output.contains("oi-do-cmd"), "saída: {output:?}");
    assert_eq!(exit, PtyExit::Code(0));
}

/// O console é aberto sem `PSEUDOCONSOLE_INHERIT_CURSOR`: ele não pergunta a
/// posição do cursor (`ESC[6n`) ao nascer. Se perguntasse, o emulador
/// responderia, e a resposta poderia cair no teclado do shell como texto.
#[test]
fn a_pergunta_do_cursor_do_conpty_nao_chega_a_saida_nem_volta_ao_filho() {
    let mut child = spawn(powershell(
        "[Threading.Thread]::Sleep(800); \"teclado-$([Console]::KeyAvailable)\"",
    ));
    let (output, exit) = child.read_to_end().unwrap();

    assert!(!output.contains("\x1b[6n"), "saída: {output:?}");
    assert!(output.contains("teclado-False"), "saída: {output:?}");
    assert_eq!(exit, PtyExit::Code(0));
}

#[test]
fn codigo_de_saida_vem_no_exited() {
    let mut child = spawn(cmd("exit 7"));
    let (_, exit) = child.read_to_end().unwrap();

    assert_eq!(exit, PtyExit::Code(7));
}

#[test]
fn escrita_chega_ao_filho() {
    let mut child = spawn(powershell("$n = [Console]::ReadLine(); \"ola-$n\""));
    child.session.write(b"mundo\r\n").unwrap();
    let (output, exit) = child.read_to_end().unwrap();

    assert!(output.contains("ola-mundo"), "saída: {output:?}");
    assert_eq!(exit, PtyExit::Code(0));
}

#[test]
fn resize_muda_o_tamanho_visto_pelo_filho() {
    let size = "('T' + [Console]::WindowWidth + 'x' + [Console]::WindowHeight)";
    let mut child = spawn(powershell(&format!(
        "{size}; $null = [Console]::ReadLine(); {size}"
    )));
    child.read_until("T80x24").unwrap();

    child
        .session
        .resize(PtySize {
            cols: 100,
            rows: 30,
        })
        .unwrap();
    child.session.write(b"\r\n").unwrap();
    let (output, _) = child.read_to_end().unwrap();

    assert!(output.contains("T100x30"), "saída: {output:?}");
}

#[test]
fn filho_roda_na_pasta_pedida() {
    let dir = tempfile::tempdir().unwrap();
    let mut pedido = cmd("echo PASTA=%CD%=");
    pedido.cwd = Some(dir.path().to_path_buf());
    let mut child = spawn(pedido);
    let (output, _) = child.read_to_end().unwrap();

    let expected = format!("PASTA={}=", dir.path().display()).to_lowercase();
    assert!(
        output.to_lowercase().contains(&expected),
        "saída: {output:?}"
    );
}

#[test]
fn pasta_do_filho_e_a_de_abertura_e_some_com_ele() {
    let dir = tempfile::tempdir().unwrap();
    let mut pedido = powershell("'pronto'; [Threading.Thread]::Sleep(300000)");
    pedido.cwd = Some(dir.path().to_path_buf());
    let mut child = spawn(pedido);
    child.read_until("pronto").unwrap();

    let seen = child.session.foreground_dir().unwrap();
    assert_eq!(
        seen.display().to_string().to_lowercase(),
        dir.path().display().to_string().to_lowercase()
    );

    child.session.signal(PtySignal::Kill).unwrap();
    child.read_to_end().unwrap();
    assert_eq!(child.session.foreground_dir(), None);
}

#[test]
fn filho_so_ve_o_ambiente_do_pedido() {
    let mut pedido = cmd("set");
    pedido.env.push(("SO_ESTA".into(), "sim".into()));
    let mut child = spawn(pedido);
    let (output, _) = child.read_to_end().unwrap();

    assert!(output.contains("SO_ESTA=sim"), "saída: {output:?}");
    assert!(
        !output.to_uppercase().contains("USERPROFILE="),
        "herdou o ambiente do teste: {output:?}"
    );
}

#[test]
fn saida_longa_chega_inteira_e_em_ordem() {
    let mut child = spawn(powershell("1..20000 | ForEach-Object { 'L' + $_ }; 'FIM'"));
    let (output, exit) = child.read_to_end().unwrap();

    let first = output.find("L1\r").or_else(|| output.find("L1\n"));
    let middle = output.find("L10000");
    let last = output.find("L20000");
    assert!(
        first.is_some() && first < middle && middle < last,
        "fora de ordem ou faltando: {} bytes",
        output.len()
    );
    assert!(output.contains("FIM"));
    assert_eq!(exit, PtyExit::Code(0));
}

/// O neto (um `ping` aberto pelo PowerShell) está no Job do terminal: o
/// `Kill` encerra a árvore, como o `killpg` do grupo no unix.
#[test]
fn kill_mata_a_arvore_inteira() {
    let mut child = spawn(powershell(
        "$i = [Diagnostics.ProcessStartInfo]::new('ping.exe', '-n 300 127.0.0.1'); \
         $i.UseShellExecute = $false; $p = [Diagnostics.Process]::Start($i); \
         ('FILHO:' + $p.Id + ':'); [Threading.Thread]::Sleep(300000)",
    ));
    let grandchild = child.read_number("FILHO:").unwrap();
    assert!(alive(grandchild), "o neto {grandchild} nem chegou a abrir");

    child.session.signal(PtySignal::Kill).unwrap();
    let (_, exit) = child.read_to_end().unwrap();

    assert_eq!(exit, PtyExit::Code(1));
    assert!(wait_gone(grandchild), "o neto {grandchild} sobreviveu");
}

/// O Windows não tem um segundo sinal tratável: o Terminate não mata, e quem
/// encerra depois do prazo é o Kill.
#[test]
fn terminate_sozinho_nao_mata_e_o_kill_encerra() {
    let mut child = spawn(powershell("'pronto'; [Threading.Thread]::Sleep(300000)"));
    child.read_until("pronto").unwrap();
    let pid = child.session.pid();

    child.session.signal(PtySignal::Terminate).unwrap();
    thread::sleep(Duration::from_secs(1));
    assert!(alive(pid), "o Terminate matou o filho");

    child.session.signal(PtySignal::Kill).unwrap();
    let (_, exit) = child.read_to_end().unwrap();
    assert_eq!(exit, PtyExit::Code(1));
}

/// O Hangup é o console fechado: o filho recebe o `CTRL_CLOSE_EVENT` e tem
/// tempo de gravar antes de sair — é o que o agente faz com a conversa. O
/// filho é este próprio executável de teste (`filho_que_grava_ao_fechar`).
#[test]
fn hangup_da_ao_filho_tempo_de_gravar_antes_de_sair() {
    let dir = tempfile::tempdir().unwrap();
    let mark = dir.path().join("gravou.txt");
    let mut pedido = cmd("");
    pedido.program = std::env::current_exe().unwrap();
    pedido.args = vec![
        "--exact".into(),
        "filho_que_grava_ao_fechar".into(),
        "--nocapture".into(),
        "--test-threads".into(),
        "1".into(),
    ];
    pedido
        .env
        .push(("EGEON_GRAVA_AO_FECHAR".into(), mark.display().to_string()));
    let mut child = spawn(pedido);
    child.read_until("FILHO-PRONTO").unwrap();

    child.session.signal(PtySignal::Hangup).unwrap();
    child.read_to_end().unwrap();

    assert_eq!(
        std::fs::read_to_string(&mark).ok().as_deref(),
        Some("fechou"),
        "o filho não gravou ao receber o CTRL_CLOSE_EVENT"
    );
}

/// Não é um teste: é o filho de `hangup_da_ao_filho_tempo_de_gravar_antes_de_sair`.
#[test]
fn filho_que_grava_ao_fechar() {
    let Some(mark) = std::env::var_os("EGEON_GRAVA_AO_FECHAR") else {
        return;
    };
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    runtime.block_on(async {
        let mut close = tokio::signal::windows::ctrl_close().unwrap();
        println!("FILHO-PRONTO");
        let _ = tokio::time::timeout(Duration::from_secs(60), close.recv()).await;
        std::fs::write(&mark, "fechou").unwrap();
    });
}

#[test]
fn hangup_encerra_o_filho() {
    let mut child = spawn(powershell("'pronto'; [Threading.Thread]::Sleep(300000)"));
    child.read_until("pronto").unwrap();
    let pid = child.session.pid();

    child.session.signal(PtySignal::Hangup).unwrap();
    child.read_to_end().unwrap();

    assert!(wait_gone(pid), "o filho {pid} sobreviveu ao Hangup");
}

#[test]
fn sinal_depois_do_fim_diz_que_acabou() {
    let mut child = spawn(cmd("exit 0"));
    child.read_to_end().unwrap();

    let result = child.session.signal(PtySignal::Kill);
    assert!(matches!(result, Err(PtyError::Gone)), "veio {result:?}");
}

#[test]
fn programa_inexistente_falha_no_spawn() {
    let mut pedido = cmd("exit 0");
    pedido.program = PathBuf::from(r"C:\nao\existe.exe");
    let result = SystemPty.spawn(pedido);

    assert!(matches!(result, Err(PtyError::Spawn { .. })));
}

#[test]
fn pid_da_sessao_e_o_do_filho() {
    let mut child = spawn(powershell("('PID:' + $PID + ':')"));
    let pid = child.session.pid();
    let (output, _) = child.read_to_end().unwrap();

    assert_eq!(
        number_after(&output, "PID:"),
        Some(pid),
        "saída: {output:?}"
    );
}

/// O console do Windows guarda a entrada num buffer que cresce: a fila não
/// chega a encher como o pty do unix. O que importa é o mesmo — escrever num
/// filho que não lê nunca trava quem chama.
#[test]
fn escrita_num_filho_que_nao_le_nao_trava_o_chamador() {
    let child = spawn(powershell("[Threading.Thread]::Sleep(300000)"));
    let chunk = vec![b'x'; 64 * 1024];
    let started = Instant::now();
    for _ in 0..200 {
        match child.session.write(&chunk) {
            Ok(()) | Err(PtyError::WriteQueueFull) => {}
            Err(other) => panic!("erro inesperado: {other}"),
        }
    }

    assert!(started.elapsed() < LIMIT, "write bloqueou o chamador");
    child.session.signal(PtySignal::Kill).unwrap();
}

#[test]
fn spawns_simultaneos_nao_trocam_a_saida_entre_si() {
    let threads: Vec<_> = (0..12)
        .map(|i| {
            thread::spawn(move || {
                let mut child = spawn(cmd(&format!("echo TOKEN-{i}-FIM")));
                (i, child.read_to_end().unwrap().0)
            })
        })
        .collect();
    for handle in threads {
        let (i, output) = handle.join().unwrap();
        assert!(
            output.contains(&format!("TOKEN-{i}-FIM")),
            "nó {i}: {output:?}"
        );
        for j in (0..12).filter(|&j| j != i) {
            assert!(
                !output.contains(&format!("TOKEN-{j}-FIM")),
                "nó {i} recebeu a saída do {j}"
            );
        }
    }
}

/// O fim pelo próprio driver (`Gone` depois que a espera colhe o filho), e não
/// pela tabela de processos: o handle que a sessão segura mantém o processo
/// encerrado à vista até ela ser largada. O volume é o da saída longa, bem
/// mais que o cano do ConPTY aguenta sem leitor.
#[test]
fn canal_largado_nao_trava_o_filho_na_saida() {
    let _slot = powershell_slots::slot();
    let child = SystemPty
        .spawn(powershell("1..20000 | ForEach-Object { 'L' + $_ }"))
        .unwrap();
    drop(child.events);

    let deadline = Instant::now() + LIMIT;
    let mut ended = false;
    while Instant::now() < deadline {
        if matches!(
            child.session.signal(PtySignal::Terminate),
            Err(PtyError::Gone)
        ) {
            ended = true;
            break;
        }
        thread::sleep(Duration::from_millis(100));
    }
    assert!(ended, "o filho ficou preso com o canal fechado");
}
