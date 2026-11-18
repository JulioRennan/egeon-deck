//! Pty de verdade: processos reais num pty real. Nada aqui toca `~/.egeon`.

use std::path::PathBuf;
use std::sync::mpsc::{self, Receiver, RecvTimeoutError};
use std::thread;
use std::time::{Duration, Instant};

use egeon_core::ports::pty::{
    PtyDriver, PtyError, PtyEvent, PtyExit, PtySession, PtySignal, PtySize, PtySpec,
};
use egeon_driver::SystemPty;

const SIZE: PtySize = PtySize { cols: 80, rows: 24 };
const LIMIT: Duration = Duration::from_secs(10);

/// Um filho com os eventos encaminhados por uma thread, para o teste esperar a
/// saída com prazo em vez de travar se algo não acabar.
struct Child {
    session: Box<dyn PtySession>,
    events: Receiver<PtyEvent>,
}

fn spec(command: &str) -> PtySpec {
    PtySpec {
        program: PathBuf::from("/bin/sh"),
        args: vec!["-c".into(), command.to_string()],
        env: vec![
            ("PATH".into(), "/usr/bin:/bin".into()),
            ("TERM".into(), "xterm-256color".into()),
        ],
        cwd: None,
        size: SIZE,
    }
}

// Auxiliar de teste: falhar no spawn reprova o teste que o chamou.
#[allow(clippy::unwrap_used)]
fn spawn(spec: PtySpec) -> Child {
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
    }
}

impl Child {
    /// Lê até a saída conter `needle`.
    fn read_until(&mut self, needle: &str) -> Result<String, String> {
        let deadline = Instant::now() + LIMIT;
        let mut seen = String::new();
        while !seen.contains(needle) {
            let left = deadline.saturating_duration_since(Instant::now());
            match self.events.recv_timeout(left) {
                Ok(PtyEvent::Output(bytes)) => seen.push_str(&String::from_utf8_lossy(&bytes)),
                Ok(PtyEvent::Exited(exit)) => {
                    return Err(format!("saiu ({exit:?}) sem {needle:?}; saída: {seen:?}"));
                }
                Err(RecvTimeoutError::Timeout) => {
                    return Err(format!("esperava {needle:?}; saída: {seen:?}"));
                }
                Err(RecvTimeoutError::Disconnected) => {
                    return Err(format!("canal fechou sem {needle:?}; saída: {seen:?}"));
                }
            }
        }
        Ok(seen)
    }

    /// Lê até o `Exited`; devolve toda a saída e como o filho saiu. Confere que
    /// o `Exited` é o último evento: o canal fecha logo depois.
    fn read_to_end(&mut self) -> Result<(String, PtyExit), String> {
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
                        String::from_utf8_lossy(&seen)
                    ));
                }
                Err(RecvTimeoutError::Disconnected) => {
                    return Err("canal fechou sem Exited".to_string());
                }
            }
        }
    }
}

#[test]
fn echo_oi_devolve_oi() {
    let mut child = spawn(spec("echo oi"));
    let (output, exit) = child.read_to_end().unwrap();

    assert_eq!(output.trim(), "oi");
    assert_eq!(exit, PtyExit::Code(0));
}

#[test]
fn codigo_de_saida_vem_no_exited() {
    let mut child = spawn(spec("exit 7"));
    let (_, exit) = child.read_to_end().unwrap();

    assert_eq!(exit, PtyExit::Code(7));
}

#[test]
fn escrita_chega_ao_filho() {
    let mut child = spawn(spec("read nome; echo \"ola $nome\""));
    child.session.write(b"mundo\n").unwrap();
    let (output, exit) = child.read_to_end().unwrap();

    assert!(output.contains("ola mundo"), "saída: {output:?}");
    assert_eq!(exit, PtyExit::Code(0));
}

#[test]
fn resize_muda_o_tamanho_visto_pelo_filho() {
    let mut child = spawn(spec("stty size; read x; stty size"));
    child.read_until("24 80").unwrap();

    child
        .session
        .resize(PtySize {
            cols: 100,
            rows: 30,
        })
        .unwrap();
    child.session.write(b"\n").unwrap();
    let (output, _) = child.read_to_end().unwrap();

    assert!(output.contains("30 100"), "saída: {output:?}");
}

#[test]
fn filho_roda_na_pasta_pedida() {
    let dir = tempfile::tempdir().unwrap();
    let mut pedido = spec("pwd -P");
    pedido.cwd = Some(dir.path().to_path_buf());
    let mut child = spawn(pedido);
    let (output, _) = child.read_to_end().unwrap();

    let esperado = dir.path().canonicalize().unwrap();
    assert_eq!(output.trim(), esperado.to_str().unwrap());
}

#[test]
fn pasta_da_frente_acompanha_o_cd_do_shell_e_some_com_o_filho() {
    let dir = tempfile::tempdir().unwrap();
    let root = dir.path().canonicalize().unwrap();
    std::fs::create_dir(root.join("sub")).unwrap();
    let mut pedido = spec("exec sh -i");
    pedido.cwd = Some(root.clone());
    let mut child = spawn(pedido);

    // Esperar o prompt: antes do `exec` o processo da frente ainda é o `sh -c`.
    child.session.write(b"echo pronto-$((1+1))\n").unwrap();
    child.read_until("pronto-2").unwrap();
    let wait_dir = |child: &Child, expected: &PathBuf| {
        let deadline = Instant::now() + LIMIT;
        while Instant::now() < deadline {
            if child.session.foreground_dir().as_ref() == Some(expected) {
                return true;
            }
            thread::sleep(Duration::from_millis(50));
        }
        false
    };
    assert!(wait_dir(&child, &root), "pasta inicial");

    child.session.write(b"cd sub\necho cd-$((2+2))\n").unwrap();
    child.read_until("cd-4").unwrap();
    assert!(wait_dir(&child, &root.join("sub")), "depois do cd");

    // Um programa em primeiro plano é o processo da frente: a pasta dele, e não
    // a do shell, que fica na raiz.
    child
        .session
        .write(b"cd ..; (cd sub && exec sleep 30)\n")
        .unwrap();
    assert!(wait_dir(&child, &root.join("sub")), "com o sleep na frente");

    child.session.signal(PtySignal::Kill).unwrap();
    child.read_to_end().unwrap();
    assert_eq!(child.session.foreground_dir(), None);
}

#[test]
fn filho_so_ve_o_ambiente_do_pedido() {
    let mut pedido = spec("env");
    pedido.env = vec![("SO_ESTA".into(), "sim".into())];
    let mut child = spawn(pedido);
    let (output, _) = child.read_to_end().unwrap();

    assert!(output.contains("SO_ESTA=sim"), "saída: {output:?}");
    assert!(
        !output.contains("HOME="),
        "herdou o ambiente do teste: {output:?}"
    );
}

#[test]
fn saida_longa_chega_inteira_e_em_ordem() {
    let mut child = spawn(spec("seq 1 20000"));
    let (output, exit) = child.read_to_end().unwrap();

    let lines: Vec<&str> = output.lines().collect();
    assert_eq!(lines.len(), 20000);
    assert_eq!(lines.first(), Some(&"1"));
    assert_eq!(lines.last(), Some(&"20000"));
    assert_eq!(exit, PtyExit::Code(0));
}

#[test]
fn kill_mata_o_grupo_inteiro() {
    // O `sleep` é neto do que o driver lançou: só morre se o sinal for ao grupo.
    let mut child = spawn(spec("sleep 300 & echo FILHO:$!; wait"));
    let mut seen = child.read_until("FILHO:").unwrap();
    if !seen
        .split("FILHO:")
        .nth(1)
        .is_some_and(|p| p.contains('\n'))
    {
        // O número do pid ainda não chegou inteiro.
        seen.push_str(&child.read_until("\n").unwrap());
    }
    let sleep_pid: i32 = seen
        .split("FILHO:")
        .nth(1)
        .and_then(|p| p.split_whitespace().next())
        .and_then(|p| p.parse().ok())
        .unwrap();

    child.session.signal(PtySignal::Kill).unwrap();
    let (_, exit) = child.read_to_end().unwrap();

    assert_eq!(exit, PtyExit::Signal(9));
    let mut morto = false;
    for _ in 0..50 {
        // SAFETY: sinal 0 só confere a existência.
        if unsafe { libc::kill(sleep_pid, 0) } != 0 {
            morto = true;
            break;
        }
        thread::sleep(Duration::from_millis(100));
    }
    assert!(morto, "o neto {sleep_pid} sobreviveu ao kill do grupo");
}

#[test]
fn terminate_encerra_quem_respeita() {
    let mut child = spawn(spec("echo pronto; sleep 300"));
    child.read_until("pronto").unwrap();

    child.session.signal(PtySignal::Terminate).unwrap();
    let (_, exit) = child.read_to_end().unwrap();

    assert_eq!(exit, PtyExit::Signal(15));
}

#[test]
fn sinal_depois_do_fim_diz_que_acabou() {
    let mut child = spawn(spec("true"));
    child.read_to_end().unwrap();

    let result = child.session.signal(PtySignal::Kill);
    assert!(matches!(result, Err(PtyError::Gone)), "veio {result:?}");
}

#[test]
fn programa_inexistente_falha_no_spawn() {
    let mut pedido = spec("true");
    pedido.program = PathBuf::from("/nao/existe");
    let result = SystemPty.spawn(pedido);

    assert!(matches!(result, Err(PtyError::Spawn { .. })));
}

#[test]
fn pid_da_sessao_e_o_do_filho() {
    let mut child = spawn(spec("echo $$"));
    let pid = child.session.pid();
    let (output, _) = child.read_to_end().unwrap();

    assert_eq!(output.trim(), pid.to_string());
}

#[test]
fn fila_de_escrita_cheia_nao_trava_o_chamador() {
    // O filho nunca lê: a entrada acumula no pty e depois na fila.
    let child = spawn(spec("sleep 300"));
    let chunk = vec![b'x'; 64 * 1024];
    let started = Instant::now();
    let mut refused = false;
    for _ in 0..2000 {
        match child.session.write(&chunk) {
            Ok(()) => {}
            Err(PtyError::WriteQueueFull) => {
                refused = true;
                break;
            }
            Err(other) => panic!("erro inesperado: {other}"),
        }
    }

    assert!(refused, "a fila nunca encheu");
    assert!(started.elapsed() < LIMIT, "write bloqueou o chamador");
    child.session.signal(PtySignal::Kill).unwrap();
}

#[test]
fn spawns_simultaneos_nao_trocam_a_saida_entre_si() {
    // Abrir vários nós de uma vez é o caso real. Sozinho este teste não
    // reproduziu a falha do `openpty` em paralelo; ela aparecia com a suíte toda
    // rodando junto.
    let threads: Vec<_> = (0..24)
        .map(|i| {
            thread::spawn(move || {
                let mut child = spawn(spec(&format!("echo TOKEN-{i}-FIM")));
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
        assert_eq!(
            output.matches("-FIM").count(),
            1,
            "nó {i} recebeu saída de outro: {output:?}"
        );
    }
}

#[test]
fn canal_largado_nao_trava_o_filho_na_saida() {
    // Sem ninguém ouvindo, o driver segue esvaziando o pty: se parasse, o buffer
    // encheria e o filho ficaria preso no `write` para sempre.
    let child = SystemPty.spawn(spec("seq 1 300000")).unwrap();
    drop(child.events);

    let deadline = Instant::now() + LIMIT;
    let mut acabou = false;
    while Instant::now() < deadline {
        // Sinal 0 só confere a existência, sem tocar no filho; o leitor colhe o
        // filho assim que ele acaba.
        // SAFETY: chamada de sistema só com inteiros.
        if unsafe { libc::kill(child.session.pid() as i32, 0) } != 0 {
            acabou = true;
            break;
        }
        thread::sleep(Duration::from_millis(50));
    }
    assert!(acabou, "o filho ficou preso com o canal fechado");
}
