//! O mesmo socket de domínio unix do macOS e do Linux, no `AF_UNIX` do Windows
//! (10 1803+), pela `uds_windows` (decisão 54): o protocolo não muda. O kernel
//! diz qual processo abriu cada conexão (`SIO_AF_UNIX_GETPEERPID`).
//!
//! Nem o std nem o tokio têm `AF_UNIX` no Windows. O socket é bloqueante: uma
//! thread aceita, e cada conexão ganha duas threads que copiam entre ele e um
//! `tokio::io::duplex`, que é o que o core lê e escreve. As conexões são
//! curtas (uma requisição cada), salvo a da UI.

use std::io::{self, Read, Write};
use std::net::Shutdown;
use std::os::windows::io::{AsRawHandle, AsRawSocket};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;

use egeon_core::log;
use egeon_core::ports::local_conn::{BoxFuture, LocalConn, LocalConnError, LocalListener, Probe};
use tokio::io::{AsyncReadExt, AsyncWriteExt, DuplexStream};
use tokio::runtime::Handle;
use tokio::sync::{Mutex as AsyncMutex, mpsc};
use uds_windows::{UnixListener, UnixStream};
use windows_sys::Win32::Networking::WinSock::{
    FD_SET, SIO_AF_UNIX_GETPEERPID, SOCKET, TIMEVAL, WSAIoctl, select,
};
use windows_sys::Win32::Storage::FileSystem::{
    BY_HANDLE_FILE_INFORMATION, GetFileInformationByHandle,
};

/// `sun_path` do Windows tem 108 bytes, com o terminador.
const MAX_PATH: usize = 107;
/// Conexões aceitas à espera do core.
const ACCEPT_QUEUE: usize = 16;
/// Buffer de cada sentido entre o socket e o core.
const BRIDGE_BUFFER: usize = 64 * 1024;
const CHUNK: usize = 16 * 1024;
/// De quanto em quanto a thread que aceita confere se a escuta foi largada.
const ACCEPT_POLL_MS: i32 = 200;

/// O arquivo do socket: série do volume e índice do arquivo, o par do
/// dispositivo e inode do unix. A hora de criação não serve: o NTFS devolve a
/// do arquivo apagado a quem é criado com o mesmo nome logo depois
/// ("tunneling").
type FileId = (u32, u64);

type Accepted = io::Result<UnixStream>;

pub(super) fn listen(path: &Path) -> Result<Box<dyn LocalListener>, LocalConnError> {
    let len = path.as_os_str().len();
    if len > MAX_PATH {
        return Err(LocalConnError::PathTooLong {
            path: path.display().to_string(),
            len,
            max: MAX_PATH,
        });
    }
    // A mesma guarda do unix: a segunda instância do mesmo flavor não toma o
    // socket da primeira.
    if let Probe::Alive { pid } = probe(path) {
        return Err(LocalConnError::AlreadyListening { pid });
    }
    match std::fs::remove_file(path) {
        Ok(()) => {}
        Err(error) if error.kind() == io::ErrorKind::NotFound => {}
        Err(error) => return Err(error.into()),
    }
    let runtime =
        Handle::try_current().map_err(|e| LocalConnError::Io(io::Error::other(e.to_string())))?;

    // A `uds_windows` cria o socket sem herança: os filhos aqui são os pty
    // dos agentes, que vivem horas.
    let listener = UnixListener::bind(path)?;
    let bound = file_id(path).ok_or_else(|| {
        LocalConnError::Io(io::Error::new(
            io::ErrorKind::NotFound,
            "o socket sumiu logo após o bind",
        ))
    })?;

    let stop = Arc::new(AtomicBool::new(false));
    let (accepted_tx, accepted) = mpsc::channel(ACCEPT_QUEUE);
    thread::Builder::new().name("socket-escuta".into()).spawn({
        let stop = stop.clone();
        move || accept_loop(&listener, &accepted_tx, &stop)
    })?;

    Ok(Box::new(Listener {
        accepted: AsyncMutex::new(accepted),
        runtime,
        path: path.to_path_buf(),
        bound,
        stop,
    }))
}

pub(super) fn probe(path: &Path) -> Probe {
    if std::fs::symlink_metadata(path).is_err() {
        return Probe::Nobody;
    }
    // Conectar e não escrever nada, como no unix: o órfão de um crash recusa
    // a conexão na hora.
    match UnixStream::connect(path) {
        Ok(stream) => Probe::Alive {
            pid: peer_pid(&stream),
        },
        Err(_) => Probe::Nobody,
    }
}

struct Listener {
    accepted: AsyncMutex<mpsc::Receiver<Accepted>>,
    runtime: Handle,
    path: PathBuf,
    bound: FileId,
    stop: Arc<AtomicBool>,
}

impl LocalListener for Listener {
    fn accept(&self) -> BoxFuture<'_, Result<LocalConn, LocalConnError>> {
        Box::pin(async move {
            let next = self.accepted.lock().await.recv().await;
            let stream = match next {
                Some(Ok(stream)) => stream,
                Some(Err(error)) => return Err(error.into()),
                None => {
                    return Err(LocalConnError::Io(io::Error::new(
                        io::ErrorKind::BrokenPipe,
                        "a escuta parou",
                    )));
                }
            };
            let peer_pid = peer_pid(&stream);
            let stream = bridge(stream, &self.runtime)?;
            Ok(LocalConn {
                peer_pid,
                stream: Box::new(stream),
            })
        })
    }

    fn is_current(&self) -> bool {
        file_id(&self.path) == Some(self.bound)
    }
}

impl Drop for Listener {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
        // Só apaga o que é nosso, como no unix.
        if self.is_current() {
            let _ = std::fs::remove_file(&self.path);
        }
    }
}

fn accept_loop(listener: &UnixListener, accepted: &mpsc::Sender<Accepted>, stop: &AtomicBool) {
    while !stop.load(Ordering::Relaxed) {
        // O `accept` bloqueante não volta quando a escuta é largada; o
        // `select` com prazo deixa a thread conferir a parada sem atrasar a
        // conexão que chega.
        match readable(listener.as_raw_socket() as SOCKET, ACCEPT_POLL_MS) {
            Ok(false) => continue,
            Ok(true) => {}
            Err(error) => {
                let _ = accepted.blocking_send(Err(error));
                return;
            }
        }
        let next = listener.accept().map(|(stream, _)| stream);
        if accepted.blocking_send(next).is_err() {
            return;
        }
    }
}

/// O socket tem conexão à espera? `false` quando o prazo passa.
fn readable(socket: SOCKET, timeout_ms: i32) -> io::Result<bool> {
    let mut set = FD_SET {
        fd_count: 1,
        fd_array: [0; 64],
    };
    set.fd_array[0] = socket;
    let timeout = TIMEVAL {
        tv_sec: timeout_ms / 1000,
        tv_usec: (timeout_ms % 1000) * 1000,
    };
    // SAFETY: o conjunto e o prazo são locais vivos; o primeiro argumento é
    // ignorado no Windows.
    let ready = unsafe {
        select(
            0,
            &mut set,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            &timeout,
        )
    };
    match ready {
        0 => Ok(false),
        n if n > 0 => Ok(true),
        _ => Err(io::Error::last_os_error()),
    }
}

/// Liga o socket bloqueante a um `DuplexStream` do runtime: uma thread por
/// sentido. Quando um lado fecha, o outro fica sabendo — o core larga a
/// conexão e o par vê o fim; o par fecha e o core lê o fim.
fn bridge(stream: UnixStream, runtime: &Handle) -> io::Result<DuplexStream> {
    let (core_side, ours) = tokio::io::duplex(BRIDGE_BUFFER);
    let (mut from_core, mut to_core) = tokio::io::split(ours);
    let inbound = stream.try_clone()?;
    let outbound = stream;

    let handle = runtime.clone();
    thread::Builder::new()
        .name("socket-entrada".into())
        .spawn(move || {
            let mut buffer = vec![0u8; CHUNK];
            let mut socket = inbound;
            loop {
                match socket.read(&mut buffer) {
                    Ok(0) | Err(_) => break,
                    Ok(n) => {
                        if handle.block_on(to_core.write_all(&buffer[..n])).is_err() {
                            break;
                        }
                    }
                }
            }
            let _ = handle.block_on(to_core.shutdown());
        })?;

    let handle = runtime.clone();
    thread::Builder::new()
        .name("socket-saida".into())
        .spawn(move || {
            let mut buffer = vec![0u8; CHUNK];
            let mut socket = outbound;
            loop {
                match handle.block_on(from_core.read(&mut buffer)) {
                    Ok(0) | Err(_) => break,
                    Ok(n) => {
                        if socket.write_all(&buffer[..n]).is_err() {
                            break;
                        }
                    }
                }
            }
            // `Both`, e não só a escrita: solta a thread de entrada presa no
            // `recv` de um par que não fecha.
            let _ = socket.shutdown(Shutdown::Both);
        })
        .inspect_err(|error| log!("socket: sem thread de saída — {error}"))?;

    Ok(core_side)
}

fn file_id(path: &Path) -> Option<FileId> {
    use std::os::windows::fs::OpenOptionsExt;
    const FILE_READ_ATTRIBUTES: u32 = 0x80;
    const FILE_FLAG_OPEN_REPARSE_POINT: u32 = 0x0020_0000;
    const FILE_FLAG_BACKUP_SEMANTICS: u32 = 0x0200_0000;
    // Sem seguir o ponto de nova análise: o socket é um, e segui-lo falha.
    let file = std::fs::OpenOptions::new()
        .access_mode(FILE_READ_ATTRIBUTES)
        .custom_flags(FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_BACKUP_SEMANTICS)
        .open(path)
        .ok()?;
    // SAFETY: estrutura zerada é válida e é preenchida pela chamada.
    let mut info: BY_HANDLE_FILE_INFORMATION = unsafe { std::mem::zeroed() };
    // SAFETY: o handle é do `File` vivo; `info` é um local vivo.
    if unsafe { GetFileInformationByHandle(file.as_raw_handle(), &mut info) } == 0 {
        return None;
    }
    let index = (u64::from(info.nFileIndexHigh) << 32) | u64::from(info.nFileIndexLow);
    Some((info.dwVolumeSerialNumber, index))
}

/// Pid do processo do outro lado, segundo o kernel — nunca o que o pedido diz.
fn peer_pid(stream: &UnixStream) -> Option<u32> {
    let mut pid: u32 = 0;
    let mut returned: u32 = 0;
    // SAFETY: a saída é um `u32` local vivo, com o tamanho declarado; sem
    // entrada, sem overlapped.
    let result = unsafe {
        WSAIoctl(
            stream.as_raw_socket() as SOCKET,
            SIO_AF_UNIX_GETPEERPID,
            std::ptr::null(),
            0,
            (&raw mut pid).cast(),
            size_of::<u32>() as u32,
            &mut returned,
            std::ptr::null_mut(),
            None,
        )
    };
    (result == 0 && pid > 0).then_some(pid)
}
