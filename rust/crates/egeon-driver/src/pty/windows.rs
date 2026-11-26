//! Pty do Windows: ConPTY (decisão 54), aberto direto pela API em `conpty`, o
//! filho num Job Object próprio e três threads por filho — a de leitura, a de
//! escrita e a que espera o filho acabar.
//!
//! O ConPTY não fecha o cano de saída quando o filho sai: quem o segura é o
//! pseudoconsole. A thread que espera o filho fecha o console depois que ele
//! acaba; o cano então chega ao fim, e só aí a leitura manda `Exited` — depois
//! de toda a saída, como no unix.

use std::fs::File;
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
use tokio::sync::mpsc;
use windows_sys::Win32::System::JobObjects::{
    AssignProcessToJobObject, CreateJobObjectW, JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION, JobObjectExtendedLimitInformation,
    SetInformationJobObject, TerminateJobObject,
};

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

use super::conpty::{self, Process, PseudoConsole};

pub(super) fn spawn(spec: PtySpec) -> Result<PtyChild, PtyError> {
    let opened = conpty::open(spec.size).map_err(|e| PtyError::Open(e.to_string()))?;
    let process = conpty::spawn(&opened.console, &spec).map_err(|e| PtyError::Spawn {
        program: spec.program.display().to_string(),
        reason: e.to_string(),
    })?;
    let process = Arc::new(process);

    let pid = process.pid;
    // O filho nasce suspenso e entra no Job antes de rodar: tudo o que ele
    // abrir (agente, `npm`) nasce dentro.
    let job = Job::adopt(process.handle());
    if let Err(error) = process.resume() {
        process.kill();
        return Err(PtyError::Spawn {
            program: spec.program.display().to_string(),
            reason: error.to_string(),
        });
    }
    let (reader, writer) = (opened.output, opened.input);

    let shared = Arc::new(Shared {
        console: Mutex::new(Some(opened.console)),
        exit: Mutex::new(None),
        job,
        process: process.clone(),
    });
    let (events_tx, events) = mpsc::channel(EVENT_CAPACITY);
    let (writer_tx, writer_rx) = std_mpsc::sync_channel::<Vec<u8>>(WRITE_QUEUE);

    let started = thread::Builder::new()
        .name("pty-espera".into())
        .spawn({
            let shared = shared.clone();
            move || waiter_loop(&process, &shared, pid)
        })
        .and_then(|_| {
            thread::Builder::new().name("pty-leitura".into()).spawn({
                let shared = shared.clone();
                move || reader_loop(reader, &shared, &events_tx)
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

/// O que as threads e a sessão dividem.
struct Shared {
    /// O pseudoconsole; `None` depois de fechado.
    console: Mutex<Option<PseudoConsole>>,
    /// O código de saída, quando o filho acabou.
    exit: Mutex<Option<PtyExit>>,
    /// `None` quando o sistema não deixou criar o Job (o app já dentro de um
    /// Job que proíbe aninhar): aí só o filho é encerrado, não a árvore.
    job: Option<Job>,
    process: Arc<Process>,
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
            self.process.kill();
        }
    }
}

/// Um Job Object que encerra tudo dentro quando o último handle fecha — o
/// app sair, até por queda, leva a árvore de cada terminal junto (ADR-084).
struct Job(OwnedHandle);

impl Job {
    fn adopt(process: windows_sys::Win32::Foundation::HANDLE) -> Option<Self> {
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
        let Some(console) = console.as_ref() else {
            return Err(PtyError::Gone);
        };
        console
            .resize(size)
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
fn waiter_loop(process: &Process, shared: &Shared, pid: u32) {
    // O código do Windows é um u32; o `as` dá o mesmo valor que o unix vê
    // nos códigos pequenos, e os de NTSTATUS saem negativos, como no Swift.
    let exit = match process.wait() {
        Ok(code) => PtyExit::Code(code as i32),
        Err(_) => PtyExit::Code(-1),
    };
    *shared.exit.lock().unwrap_or_else(PoisonError::into_inner) = Some(exit);
    // Os dois passos do fim no log: um terminal que não fecha mostra se foi o
    // filho que não saiu ou o `ClosePseudoConsole` que não voltou.
    log!("pty {pid}: o filho saiu ({exit:?}); fechando o console");
    shared.close_console();
    log!("pty {pid}: console fechado");
}

fn reader_loop(mut reader: File, shared: &Shared, events: &mpsc::Sender<PtyEvent>) {
    let mut buffer = vec![0u8; READ_CHUNK];
    // Se o runtime largou o canal, segue lendo e descartando: parar de ler
    // encheria o cano e o filho travaria — e o `ClosePseudoConsole` também,
    // que espera a saída escoar.
    let mut listening = true;
    loop {
        match reader.read(&mut buffer) {
            Ok(0) | Err(_) => break,
            Ok(n) => {
                listening = listening
                    && events
                        .blocking_send(PtyEvent::Output(buffer[..n].to_vec()))
                        .is_ok();
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

fn writer_loop(mut writer: File, queue: &std_mpsc::Receiver<Vec<u8>>) {
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
