//! Pty do Windows: ConPTY pela `portable-pty` (decisão 54), o filho num Job
//! Object próprio e três threads por filho — a de leitura, a de escrita e a
//! que espera o filho acabar.
//!
//! O ConPTY não fecha o cano de saída quando o filho sai: quem o segura é o
//! pseudoconsole. A thread que espera o filho fecha o console depois que ele
//! acaba; o cano então chega ao fim, e só aí a leitura manda `Exited` — depois
//! de toda a saída, como no unix.

use std::io::{Read, Write};
use std::os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle};
use std::path::PathBuf;
use std::sync::mpsc::{self as std_mpsc, TrySendError};
use std::sync::{Arc, Mutex, PoisonError};
use std::thread;
use std::time::Duration;

use egeon_core::log;
use egeon_core::ports::pty::{
    PtyChild, PtyError, PtyEvent, PtyExit, PtySession, PtySignal, PtySize, PtySpec,
};
use portable_pty::{Child, CommandBuilder, MasterPty, PtySize as ConSize, native_pty_system};
use tokio::sync::mpsc;
use windows_sys::Win32::System::JobObjects::{
    AssignProcessToJobObject, CreateJobObjectW, JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION, JobObjectExtendedLimitInformation,
    SetInformationJobObject, TerminateJobObject,
};
use windows_sys::Win32::System::Threading::{OpenProcess, PROCESS_SET_QUOTA, PROCESS_TERMINATE};

/// Os mesmos limites do unix: o canal cheio para a leitura, e a contrapressão
/// chega a quem escreve.
const EVENT_CAPACITY: usize = 64;
const READ_CHUNK: usize = 16 * 1024;
const WRITE_QUEUE: usize = 256;
/// O Ctrl-C no ConPTY: com a entrada processada (o padrão do console), o byte
/// vira o `CTRL_C_EVENT` dos processos ligados ao console, que é o SIGINT do
/// grupo no unix.
const CTRL_C: u8 = 0x03;
/// O código de saída de quem o Job encerra.
const KILLED_EXIT: u32 = 1;
/// Quanto a leitura espera o filho depois do fim do cano: o Windows dá 5 s a
/// quem recebe o `CTRL_CLOSE_EVENT` antes de encerrá-lo.
const EXIT_WAIT: Duration = Duration::from_millis(20);
const EXIT_WAIT_TRIES: usize = 400;
/// A `portable-pty` cria o ConPTY com `PSEUDOCONSOLE_INHERIT_CURSOR`: antes de
/// qualquer saída do filho, o console pergunta a posição do cursor (DSR) e
/// segura o filho até ter resposta. A pergunta é do ConPTY, não do programa:
/// o driver responde (o terminal acabou de nascer, cursor no canto) e a tira
/// da saída, para o emulador não responder de novo.
const CURSOR_QUERY: &[u8] = b"\x1b[6n";
const CURSOR_AT_ORIGIN: &[u8] = b"\x1b[1;1R";
/// Até onde a pergunta do ConPTY pode vir: ele a manda logo no começo, no
/// máximo depois de ligar alguns modos.
const CURSOR_QUERY_WINDOW: usize = 64;

pub(super) fn spawn(spec: PtySpec) -> Result<PtyChild, PtyError> {
    let pair = native_pty_system()
        .openpty(con_size(spec.size))
        .map_err(|e| PtyError::Open(e.to_string()))?;

    let program = spec.program.display().to_string();
    let mut command = CommandBuilder::new(&spec.program);
    command.args(&spec.args);
    command.env_clear();
    for (key, value) in &spec.env {
        command.env(key, value);
    }
    if let Some(cwd) = &spec.cwd {
        command.cwd(cwd);
    }
    let mut child = pair
        .slave
        .spawn_command(command)
        .map_err(|e| PtyError::Spawn {
            program: program.clone(),
            reason: e.to_string(),
        })?;
    // O lado escravo só serve para lançar; o console fica com o mestre.
    drop(pair.slave);

    let pid = child.process_id().unwrap_or_default();
    // O filho entra no Job logo depois de nascer: o que ele abrir dali em
    // diante (agente, `npm`) nasce dentro. O PowerShell leva bem mais que isso
    // para abrir o primeiro filho.
    let job = child.as_raw_handle().and_then(Job::adopt);
    // O que o filho já abriu antes de entrar no Job nasceu fora dele: entra
    // agora. Fecha quase toda a janela; o que nascer no meio desta varredura
    // ainda escapa.
    if let Some(job) = &job {
        job.adopt_descendants(pid);
    }
    let killer = child.clone_killer();

    let reader = pair
        .master
        .try_clone_reader()
        .map_err(|e| PtyError::Open(e.to_string()))?;
    let writer = pair
        .master
        .take_writer()
        .map_err(|e| PtyError::Open(e.to_string()))?;

    let shared = Arc::new(Shared {
        console: Mutex::new(Some(pair.master)),
        exit: Mutex::new(None),
        job,
        killer: Mutex::new(killer),
    });
    let (events_tx, events) = mpsc::channel(EVENT_CAPACITY);
    let (writer_tx, writer_rx) = std_mpsc::sync_channel::<Vec<u8>>(WRITE_QUEUE);

    let started = thread::Builder::new()
        .name("pty-espera".into())
        .spawn({
            let shared = shared.clone();
            move || waiter_loop(&mut child, &shared)
        })
        .and_then(|_| {
            thread::Builder::new().name("pty-leitura".into()).spawn({
                let shared = shared.clone();
                let replies = writer_tx.clone();
                move || reader_loop(reader, &shared, &events_tx, &replies)
            })
        })
        .and_then(|_| {
            thread::Builder::new()
                .name("pty-escrita".into())
                .spawn(move || writer_loop(writer, &writer_rx))
        });
    if let Err(error) = started {
        // Sem as threads ninguém colhe nem lê: o filho morre aqui em vez de
        // ficar vivo sem dono.
        shared.terminate();
        shared.close_console();
        return Err(PtyError::Io(error.to_string()));
    }

    Ok(PtyChild {
        session: Box::new(Session {
            pid,
            shared,
            writer: writer_tx,
        }),
        events,
    })
}

fn con_size(size: PtySize) -> ConSize {
    ConSize {
        rows: size.rows,
        cols: size.cols,
        pixel_width: 0,
        pixel_height: 0,
    }
}

/// O que as threads e a sessão dividem.
struct Shared {
    /// O mestre segura o pseudoconsole; `None` depois de fechado.
    console: Mutex<Option<Box<dyn MasterPty + Send>>>,
    /// O código de saída, quando o filho acabou.
    exit: Mutex<Option<PtyExit>>,
    /// `None` quando o sistema não deixou criar o Job (o app já dentro de um
    /// Job que proíbe aninhar): aí só o filho é encerrado, não a árvore.
    job: Option<Job>,
    killer: Mutex<Box<dyn portable_pty::ChildKiller + Send + Sync>>,
}

impl Shared {
    fn exited(&self) -> Option<PtyExit> {
        *self.exit.lock().unwrap_or_else(PoisonError::into_inner)
    }

    /// Fechar o console, como o mestre fechado no unix: os processos ligados
    /// a ele recebem o `CTRL_CLOSE_EVENT` e saem.
    fn close_console(&self) {
        let console = self
            .console
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .take();
        drop(console);
    }

    /// A árvore toda pelo Job; sem Job, só o filho.
    fn terminate(&self) {
        let killed = self.job.as_ref().is_some_and(Job::terminate);
        if !killed {
            let _ = self
                .killer
                .lock()
                .unwrap_or_else(PoisonError::into_inner)
                .kill();
        }
    }
}

/// Um Job Object que encerra tudo dentro quando o último handle fecha — o
/// app sair, até por queda, leva a árvore de cada terminal junto (ADR-084).
struct Job(OwnedHandle);

impl Job {
    fn adopt(process: std::os::windows::io::RawHandle) -> Option<Self> {
        // SAFETY: atributos e nome nulos são aceitos; o handle devolvido é
        // nosso e passa a ser do `OwnedHandle`.
        let raw = unsafe { CreateJobObjectW(std::ptr::null(), std::ptr::null()) };
        if raw.is_null() {
            log!("pty: sem Job Object ({})", std::io::Error::last_os_error());
            return None;
        }
        // SAFETY: `raw` é um handle novo e válido, só nosso.
        let job = Job(unsafe { OwnedHandle::from_raw_handle(raw) });
        // SAFETY: estrutura zerada é válida; só o campo do limite é preenchido.
        let mut limits: JOBOBJECT_EXTENDED_LIMIT_INFORMATION = unsafe { std::mem::zeroed() };
        limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        // SAFETY: ponteiro para um local vivo, com o tamanho declarado.
        let set = unsafe {
            SetInformationJobObject(
                job.handle(),
                JobObjectExtendedLimitInformation,
                (&raw const limits).cast(),
                size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
            )
        };
        // SAFETY: os dois handles são válidos durante a chamada.
        if set == 0 || unsafe { AssignProcessToJobObject(job.handle(), process) } == 0 {
            log!(
                "pty: o filho ficou fora do Job ({})",
                std::io::Error::last_os_error()
            );
            return None;
        }
        Some(job)
    }

    /// Põe no Job os descendentes de `root` que já existem.
    fn adopt_descendants(&self, root: u32) {
        let all = crate::procs::tree();
        for process in egeon_core::ports::procs::descendants(root, &all) {
            // SAFETY: sem pré-condição; o handle, se vier, é nosso.
            let raw = unsafe { OpenProcess(PROCESS_SET_QUOTA | PROCESS_TERMINATE, 0, process.pid) };
            if raw.is_null() {
                continue;
            }
            // SAFETY: handle novo e válido, só nosso.
            let handle = unsafe { OwnedHandle::from_raw_handle(raw) };
            // SAFETY: os dois handles são válidos durante a chamada.
            unsafe { AssignProcessToJobObject(self.handle(), handle.as_raw_handle()) };
        }
    }

    fn handle(&self) -> windows_sys::Win32::Foundation::HANDLE {
        self.0.as_raw_handle()
    }

    fn terminate(&self) -> bool {
        // SAFETY: o handle do Job é válido enquanto `self` vive.
        unsafe { TerminateJobObject(self.handle(), KILLED_EXIT) != 0 }
    }
}

struct Session {
    pid: u32,
    shared: Arc<Shared>,
    writer: std_mpsc::SyncSender<Vec<u8>>,
}

impl PtySession for Session {
    fn pid(&self) -> u32 {
        self.pid
    }

    fn write(&self, data: &[u8]) -> Result<(), PtyError> {
        if data.is_empty() {
            return Ok(());
        }
        self.writer.try_send(data.to_vec()).map_err(|e| match e {
            TrySendError::Full(_) => PtyError::WriteQueueFull,
            TrySendError::Disconnected(_) => PtyError::Gone,
        })
    }

    fn resize(&self, size: PtySize) -> Result<(), PtyError> {
        let console = self
            .shared
            .console
            .lock()
            .unwrap_or_else(PoisonError::into_inner);
        let Some(master) = console.as_ref() else {
            return Err(PtyError::Gone);
        };
        master
            .resize(con_size(size))
            .map_err(|e| PtyError::Io(e.to_string()))
    }

    fn foreground_dir(&self) -> Option<PathBuf> {
        // O Windows não tem grupo da frente no console: vale a pasta do filho.
        // O `Set-Location` do PowerShell não muda a pasta do processo, então
        // depois de um `cd` no PowerShell isto ainda diz a pasta de abertura.
        if self.shared.exited().is_some() {
            return None;
        }
        crate::procs::cwd_of(self.pid)
    }

    fn signal(&self, signal: PtySignal) -> Result<(), PtyError> {
        if self.shared.exited().is_some() {
            return Err(PtyError::Gone);
        }
        match signal {
            PtySignal::Interrupt => self.write(&[CTRL_C]),
            // O fechar do app manda Hangup e Terminate e espera um prazo antes
            // do Kill: é quando o agente grava a conversa e sai sozinho. Fechar
            // o console é o que o processo pode tratar (`CTRL_CLOSE_EVENT`, que
            // o node entrega como SIGHUP, com uns 5 s para sair). O Windows
            // não tem um segundo sinal tratável: o Terminate não acrescenta
            // nada. Só o Kill encerra a árvore pelo Job (decisão 54).
            PtySignal::Hangup => {
                self.close_console_in_background();
                Ok(())
            }
            PtySignal::Terminate => Ok(()),
            PtySignal::Kill => {
                self.shared.terminate();
                Ok(())
            }
        }
    }
}

impl Session {
    /// Numa thread: no Windows 10 o `ClosePseudoConsole` espera o conhost
    /// escoar a saída, e quem chama é o ator.
    fn close_console_in_background(&self) {
        let shared = self.shared.clone();
        let closed = thread::Builder::new()
            .name("pty-fecha".into())
            .spawn(move || shared.close_console());
        if closed.is_err() {
            self.shared.close_console();
        }
    }
}

impl Drop for Session {
    fn drop(&mut self) {
        // Largar a sessão fecha o terminal, como o mestre fechado no unix.
        self.close_console_in_background();
    }
}

/// Espera o filho; quando ele acaba, guarda o código e fecha o console, que
/// solta o fim da saída para a leitura.
fn waiter_loop(child: &mut Box<dyn Child + Send + Sync>, shared: &Shared) {
    let exit = match child.wait() {
        Ok(status) => PtyExit::Code(status.exit_code() as i32),
        Err(_) => PtyExit::Code(-1),
    };
    *shared.exit.lock().unwrap_or_else(PoisonError::into_inner) = Some(exit);
    shared.close_console();
}

fn reader_loop(
    mut reader: Box<dyn Read + Send>,
    shared: &Shared,
    events: &mpsc::Sender<PtyEvent>,
    replies: &std_mpsc::SyncSender<Vec<u8>>,
) {
    let mut buffer = vec![0u8; READ_CHUNK];
    let mut handshake = Handshake::default();
    // Se o runtime largou o canal, segue lendo e descartando: parar de ler
    // encheria o cano e o filho travaria — e o `ClosePseudoConsole` também,
    // que espera a saída escoar.
    let mut listening = true;
    loop {
        match reader.read(&mut buffer) {
            Ok(0) | Err(_) => break,
            Ok(n) => {
                let mut chunk = buffer[..n].to_vec();
                if handshake.take_query(&mut chunk) {
                    let _ = replies.try_send(CURSOR_AT_ORIGIN.to_vec());
                }
                if !chunk.is_empty() {
                    listening = listening && events.blocking_send(PtyEvent::Output(chunk)).is_ok();
                }
            }
        }
    }
    // O cano só chega ao fim com o console fechado: pelo filho que acabou (o
    // código já está guardado) ou pela sessão largada — aí o filho recebeu o
    // `CTRL_CLOSE_EVENT` e sai em seguida; `Exited` espera por ele.
    let mut exit = shared.exited();
    for _ in 0..EXIT_WAIT_TRIES {
        if exit.is_some() {
            break;
        }
        thread::sleep(EXIT_WAIT);
        exit = shared.exited();
    }
    let exit = exit.unwrap_or(PtyExit::Code(KILLED_EXIT as i32));
    if listening {
        let _ = events.blocking_send(PtyEvent::Exited(exit));
    }
}

/// A pergunta do cursor que o ConPTY faz ao nascer, só ela: as que o
/// programa fizer depois vão ao emulador.
#[derive(Default)]
struct Handshake {
    seen: usize,
    done: bool,
}

impl Handshake {
    fn take_query(&mut self, chunk: &mut Vec<u8>) -> bool {
        if self.done {
            return false;
        }
        // A pergunta pode começar dentro da janela e terminar fora dela.
        let end = (CURSOR_QUERY_WINDOW.saturating_sub(self.seen) + CURSOR_QUERY.len() - 1)
            .min(chunk.len());
        let found = chunk[..end]
            .windows(CURSOR_QUERY.len())
            .position(|w| w == CURSOR_QUERY);
        self.seen += chunk.len();
        if let Some(at) = found {
            chunk.drain(at..at + CURSOR_QUERY.len());
            self.done = true;
            return true;
        }
        self.done = self.seen >= CURSOR_QUERY_WINDOW;
        false
    }
}

fn writer_loop(mut writer: Box<dyn Write + Send>, queue: &std_mpsc::Receiver<Vec<u8>>) {
    while let Ok(chunk) = queue.recv() {
        if writer
            .write_all(&chunk)
            .and_then(|()| writer.flush())
            .is_err()
        {
            return;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::Handshake;

    #[test]
    fn a_pergunta_do_conpty_sai_da_saida_uma_vez_so() {
        let mut handshake = Handshake::default();
        let mut first = b"\x1b[?9001h\x1b[?1004h\x1b[6n".to_vec();
        assert!(handshake.take_query(&mut first));
        assert_eq!(first, b"\x1b[?9001h\x1b[?1004h");

        let mut later = b"PS> \x1b[6n".to_vec();
        assert!(!handshake.take_query(&mut later));
        assert_eq!(later, b"PS> \x1b[6n");
    }

    #[test]
    fn saida_comum_no_comeco_encerra_a_espera() {
        let mut handshake = Handshake::default();
        let mut output = vec![b'x'; 80];
        assert!(!handshake.take_query(&mut output));
        let mut late = b"\x1b[6n".to_vec();
        assert!(!handshake.take_query(&mut late));
        assert_eq!(late, b"\x1b[6n");
    }
}
