//! Pty de sistema unix: `openpty`, o filho como líder de sessão com o pty de
//! terminal de controle, e duas threads por filho: a de leitura, que também colhe
//! o código de saída, e a de escrita.

use std::io;
use std::os::fd::{AsRawFd, FromRawFd, OwnedFd, RawFd};
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self as std_mpsc, TrySendError};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use egeon_core::ports::pty::{
    PtyChild, PtyError, PtyEvent, PtyExit, PtySession, PtySignal, PtySize, PtySpec,
};
use tokio::sync::mpsc;

/// Pedaços de saída em voo entre o leitor e o runtime. Com o canal cheio o
/// leitor para de ler, o buffer do pty enche e o filho é quem espera — a
/// contrapressão chega até quem escreve, em vez de a memória crescer.
const EVENT_CAPACITY: usize = 64;
const READ_CHUNK: usize = 16 * 1024;
/// Entradas enfileiradas para o filho antes de `write` recusar.
const WRITE_QUEUE: usize = 256;
/// De quanto em quanto o leitor confere se o filho acabou.
const POLL_MS: i32 = 100;

static OPENPTY: Mutex<()> = Mutex::new(());

pub(super) fn spawn(spec: PtySpec) -> Result<PtyChild, PtyError> {
    // Em macOS, `openpty` chamado por várias threads ao mesmo tempo falhou ao
    // acaso (erro -6, sem errno) em cerca de 1 de cada 12 rodadas da suíte de
    // teste, e deixou de falhar com a serialização; o `ptsname` por baixo usa um
    // buffer estático e pode entregar o escravo de um nó a outro. O cadeado vai
    // até o fim do `spawn` do processo: entre abrir os fds e marcá-los CLOEXEC,
    // um fork de outro spawn herdaria o mestre, e um mestre herdado impede o
    // SIGHUP quando o nó fecha.
    let serial = OPENPTY
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let (master, slave) = open_pty(spec.size)?;

    let program = spec.program.display().to_string();
    let spawn_error = |error: io::Error| PtyError::Spawn {
        program: program.clone(),
        reason: error.to_string(),
    };

    let mut command = Command::new(&spec.program);
    command
        .args(&spec.args)
        .env_clear()
        .envs(spec.env.iter().map(|(k, v)| (k, v)));
    if let Some(cwd) = &spec.cwd {
        command.current_dir(cwd);
    }
    command
        .stdin(Stdio::from(slave.try_clone().map_err(spawn_error)?))
        .stdout(Stdio::from(slave.try_clone().map_err(spawn_error)?))
        .stderr(Stdio::from(slave));
    // SAFETY: só chamadas async-signal-safe entre o fork e o exec.
    unsafe {
        command.pre_exec(|| {
            // Sessão própria com o pty como terminal de controle: é o que faz
            // Ctrl-C e o job control do shell funcionarem, e o filho ser líder
            // do grupo que `signal` mira.
            if libc::setsid() < 0 {
                return Err(io::Error::last_os_error());
            }
            if libc::ioctl(0, libc::TIOCSCTTY as _, 0) < 0 {
                return Err(io::Error::last_os_error());
            }
            Ok(())
        });
    }
    let child = command.spawn().map_err(spawn_error)?;
    drop(serial);
    // O `Command` guarda cópias do slave: se ficassem abertas aqui, o leitor
    // nunca veria o fim da saída.
    drop(command);

    let pid = child.id() as i32;
    let master = Arc::new(master);
    let state = Arc::new(Mutex::new(ChildState {
        child: Some(child),
        live_pid: Some(pid),
        exit: None,
    }));
    let closed = Arc::new(AtomicBool::new(false));
    let (events_tx, events) = mpsc::channel(EVENT_CAPACITY);
    let (writer_tx, writer_rx) = std_mpsc::sync_channel(WRITE_QUEUE);

    let started = thread::Builder::new()
        .name("pty-leitura".into())
        .spawn({
            let (master, state, closed) = (master.clone(), state.clone(), closed.clone());
            move || reader_loop(master, state, events_tx, closed)
        })
        .and_then(|_| {
            thread::Builder::new().name("pty-escrita".into()).spawn({
                let (master, closed) = (master.clone(), closed.clone());
                move || writer_loop(master, writer_rx, closed)
            })
        });
    if let Err(error) = started {
        // A thread de leitura pode já estar de pé segurando o mestre: sem isto o
        // shell nunca receberia SIGHUP e ficaria vivo sem dono.
        closed.store(true, Ordering::Relaxed);
        return Err(PtyError::Io(error.to_string()));
    }

    Ok(PtyChild {
        session: Box::new(Session {
            pid,
            master,
            state,
            writer: writer_tx,
            closed,
        }),
        events,
    })
}

/// O filho e o que se sabe dele, atrás de um cadeado só: colher e sinalizar não
/// podem se cruzar, ou o sinal mira um pid que o sistema já deu a outro processo.
struct ChildState {
    /// `None` depois de colhido.
    child: Option<Child>,
    /// O pid enquanto o filho não foi colhido.
    live_pid: Option<i32>,
    exit: Option<PtyExit>,
}

impl Drop for ChildState {
    fn drop(&mut self) {
        // Os dois lados foram largados sem o filho acabar. Sem colher, ele vira
        // zumbi até o app sair; uma thread pequena espera por ele.
        if let Some(mut child) = self.child.take() {
            thread::spawn(move || {
                let _ = child.wait();
            });
        }
    }
}

/// Colhe o filho se ele já terminou. Devolve o código quando acabou.
fn reap(state: &Mutex<ChildState>) -> Option<PtyExit> {
    let mut state = state.lock().ok()?;
    if state.exit.is_some() {
        return state.exit;
    }
    let status = state.child.as_mut()?.try_wait();
    let exit = match status {
        Ok(None) => return None,
        Ok(Some(status)) => exit_of(status),
        Err(_) => PtyExit::Code(-1),
    };
    state.child = None;
    state.live_pid = None;
    state.exit = Some(exit);
    Some(exit)
}

fn exit_of(status: std::process::ExitStatus) -> PtyExit {
    match (status.code(), status.signal()) {
        (Some(code), _) => PtyExit::Code(code),
        (None, Some(signal)) => PtyExit::Signal(signal),
        (None, None) => PtyExit::Code(-1),
    }
}

struct Session {
    pid: i32,
    master: Arc<OwnedFd>,
    state: Arc<Mutex<ChildState>>,
    writer: std_mpsc::SyncSender<Vec<u8>>,
    closed: Arc<AtomicBool>,
}

impl PtySession for Session {
    fn pid(&self) -> u32 {
        self.pid as u32
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
        let winsize = winsize(size);
        // SAFETY: `winsize` vive até o fim da chamada e o fd é do `OwnedFd`.
        let result = unsafe { libc::ioctl(self.master.as_raw_fd(), libc::TIOCSWINSZ, &winsize) };
        if result < 0 {
            return Err(PtyError::Io(io::Error::last_os_error().to_string()));
        }
        Ok(())
    }

    fn foreground_dir(&self) -> Option<PathBuf> {
        reap(&self.state);
        let state = self.state.lock().ok()?;
        state.live_pid?;
        // SAFETY: `tcgetpgrp` só lê o fd, que é do `OwnedFd`.
        let group = unsafe { libc::tcgetpgrp(self.master.as_raw_fd()) };
        drop(state);
        let pid = if group > 0 { group } else { self.pid };
        crate::procs::cwd_of(u32::try_from(pid).ok()?)
    }

    fn signal(&self, signal: PtySignal) -> Result<(), PtyError> {
        let number = match signal {
            PtySignal::Hangup => libc::SIGHUP,
            PtySignal::Interrupt => libc::SIGINT,
            PtySignal::Terminate => libc::SIGTERM,
            PtySignal::Kill => libc::SIGKILL,
        };
        // Colhe antes: um filho que já acabou não pode receber sinal.
        reap(&self.state);
        let state = self.state.lock().map_err(|_| PtyError::Gone)?;
        let Some(pid) = state.live_pid else {
            return Err(PtyError::Gone);
        };
        // SAFETY: chamadas de sistema só com inteiros, e o cadeado garante que o
        // pid ainda é o do filho. A guarda do grupo não é decoração: se o pgid
        // não fosse o do filho, poderia ser o do próprio app, e o `killpg`
        // levaria o Egeon inteiro.
        let result = unsafe {
            if pid > 1 && libc::getpgid(pid) == pid {
                libc::killpg(pid, number)
            } else {
                libc::kill(pid, number)
            }
        };
        if result < 0 {
            return Err(PtyError::Io(io::Error::last_os_error().to_string()));
        }
        Ok(())
    }
}

impl Drop for Session {
    fn drop(&mut self) {
        self.closed.store(true, Ordering::Relaxed);
    }
}

/// Lê o pty e entrega ao runtime; ao fim, colhe o filho e manda `Exited`.
fn reader_loop(
    master: Arc<OwnedFd>,
    state: Arc<Mutex<ChildState>>,
    events: mpsc::Sender<PtyEvent>,
    closed: Arc<AtomicBool>,
) {
    let fd = master.as_raw_fd();
    let mut buffer = vec![0u8; READ_CHUNK];
    let mut master = Some(master);
    // Se o runtime largou o canal, a saída não tem para onde ir. Segue lendo e
    // descartando: parar de ler encheria o buffer do pty e o filho travaria.
    let mut listening = true;
    let mut eof = false;

    let exit = loop {
        if master.is_some() && closed.load(Ordering::Relaxed) {
            // Sessão largada: solta a nossa ponta. Com a sessão e a thread de
            // escrita também fora, o último fd fecha e o filho recebe SIGHUP.
            master = None;
        }
        if master.is_some() && !eof {
            match poll(fd, libc::POLLIN, POLL_MS) {
                Ok(Wait::Ready) => match read(fd, &mut buffer) {
                    Read::Data(n) => listening = deliver(&events, &buffer[..n], listening),
                    Read::Empty => {}
                    Read::End => eof = true,
                },
                Ok(Wait::Timeout) => {}
                // Sem isto o laço giraria sem dormir até o filho acabar.
                Err(_) => eof = true,
            }
        } else {
            thread::sleep(Duration::from_millis(50));
        }
        if let Some(exit) = reap(&state) {
            break exit;
        }
    };

    // O que o filho escreveu antes de morrer ainda está no buffer do pty. Sem
    // esta limpeza o fim da saída (onde ficam os erros) se perderia. É só do
    // filho: saída de um neto que ainda segura o terminal depois dele não é
    // esperada.
    while master.is_some() && !eof {
        match read(fd, &mut buffer) {
            Read::Data(n) => listening = deliver(&events, &buffer[..n], listening),
            Read::Empty | Read::End => break,
        }
    }
    if listening {
        let _ = events.blocking_send(PtyEvent::Exited(exit));
    }
}

/// Manda a saída ao runtime. Devolve se ele ainda escuta.
fn deliver(events: &mpsc::Sender<PtyEvent>, bytes: &[u8], listening: bool) -> bool {
    listening
        && events
            .blocking_send(PtyEvent::Output(bytes.to_vec()))
            .is_ok()
}

fn winsize(size: PtySize) -> libc::winsize {
    libc::winsize {
        ws_row: size.rows,
        ws_col: size.cols,
        ws_xpixel: 0,
        ws_ypixel: 0,
    }
}

fn open_pty(size: PtySize) -> Result<(OwnedFd, OwnedFd), PtyError> {
    let (mut master, mut slave) = (-1, -1);
    let mut winsize = winsize(size);
    // SAFETY: ponteiros para locais vivos; `openpty` aceita nulo no nome e no termios.
    // Ponteiro cru, e não `&mut`: o macOS declara o `winsize` mutável e o Linux
    // constante, e o `*mut` serve aos dois.
    let result = unsafe {
        libc::openpty(
            &mut master,
            &mut slave,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            &raw mut winsize,
        )
    };
    if result < 0 {
        return Err(PtyError::Open(io::Error::last_os_error().to_string()));
    }
    // SAFETY: `openpty` devolveu dois fds novos que só nós temos.
    let (master, slave) = unsafe { (OwnedFd::from_raw_fd(master), OwnedFd::from_raw_fd(slave)) };

    let fail = |e: io::Error| PtyError::Open(e.to_string());
    // Sem CLOEXEC os fds vazam para tudo que o app lançar depois.
    set_flag(master.as_raw_fd(), FdFlag::CloseOnExec).map_err(fail)?;
    set_flag(slave.as_raw_fd(), FdFlag::CloseOnExec).map_err(fail)?;
    // Sem bloqueio no mestre: a escrita num filho que não lê não pode travar a thread.
    set_flag(master.as_raw_fd(), FdFlag::NonBlocking).map_err(fail)?;
    utf8_input(master.as_raw_fd());
    Ok((master, slave))
}

enum FdFlag {
    CloseOnExec,
    NonBlocking,
}

fn set_flag(fd: RawFd, flag: FdFlag) -> io::Result<()> {
    let (get, set, bit) = match flag {
        FdFlag::CloseOnExec => (libc::F_GETFD, libc::F_SETFD, libc::FD_CLOEXEC),
        FdFlag::NonBlocking => (libc::F_GETFL, libc::F_SETFL, libc::O_NONBLOCK),
    };
    // SAFETY: `fcntl` só com inteiros, num fd aberto.
    unsafe {
        let current = libc::fcntl(fd, get);
        if current < 0 || libc::fcntl(fd, set, current | bit) < 0 {
            return Err(io::Error::last_os_error());
        }
    }
    Ok(())
}

/// Avisa o terminal que a entrada é UTF-8, para o Backspace apagar um caractere
/// e não um byte. Falhar aqui não impede nada, então o erro é ignorado.
fn utf8_input(fd: RawFd) {
    // SAFETY: `termios` é preenchido por `tcgetattr` antes de ser lido.
    unsafe {
        let mut termios: libc::termios = std::mem::zeroed();
        if libc::tcgetattr(fd, &mut termios) == 0 {
            termios.c_iflag |= libc::IUTF8;
            libc::tcsetattr(fd, libc::TCSANOW, &termios);
        }
    }
}

enum Wait {
    Ready,
    Timeout,
}

fn poll(fd: RawFd, events: libc::c_short, timeout_ms: i32) -> io::Result<Wait> {
    let mut entry = libc::pollfd {
        fd,
        events,
        revents: 0,
    };
    // SAFETY: um `pollfd` válido, contagem 1.
    let result = unsafe { libc::poll(&mut entry, 1, timeout_ms) };
    match result {
        0 => Ok(Wait::Timeout),
        n if n > 0 => Ok(Wait::Ready),
        _ => {
            let error = io::Error::last_os_error();
            if error.kind() == io::ErrorKind::Interrupted {
                Ok(Wait::Timeout)
            } else {
                Err(error)
            }
        }
    }
}

enum Read {
    Data(usize),
    /// Nada agora, mas pode vir mais.
    Empty,
    /// O outro lado fechou (EIO no mestre é o fim da saída) ou o fd quebrou.
    End,
}

fn read(fd: RawFd, buffer: &mut [u8]) -> Read {
    // SAFETY: `buffer` é um slice vivo com o tamanho passado.
    let n = unsafe { libc::read(fd, buffer.as_mut_ptr().cast(), buffer.len()) };
    match n {
        0 => Read::End,
        n if n > 0 => Read::Data(n as usize),
        _ => match io::Error::last_os_error().kind() {
            io::ErrorKind::WouldBlock | io::ErrorKind::Interrupted => Read::Empty,
            _ => Read::End,
        },
    }
}

fn writer_loop(master: Arc<OwnedFd>, queue: std_mpsc::Receiver<Vec<u8>>, closed: Arc<AtomicBool>) {
    let fd = master.as_raw_fd();
    while let Ok(chunk) = queue.recv() {
        let mut rest = chunk.as_slice();
        while !rest.is_empty() {
            if closed.load(Ordering::Relaxed) {
                return;
            }
            // SAFETY: `rest` é um slice vivo com o tamanho passado.
            let n = unsafe { libc::write(fd, rest.as_ptr().cast(), rest.len()) };
            if n >= 0 {
                rest = &rest[n as usize..];
                continue;
            }
            match io::Error::last_os_error().kind() {
                io::ErrorKind::Interrupted => {}
                // Buffer do pty cheio: o filho ainda não leu. Espera, e confere
                // `closed` a cada volta para não prender a thread para sempre.
                io::ErrorKind::WouldBlock => {
                    let _ = poll(fd, libc::POLLOUT, POLL_MS);
                }
                _ => return,
            }
        }
    }
}
