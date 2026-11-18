//! Socket de domínio unix: nada exposto na rede, e o kernel diz qual processo
//! abriu cada conexão (`LOCAL_PEERPID`).

use std::io;
use std::os::fd::{AsRawFd, RawFd};
use std::os::unix::fs::MetadataExt;
use std::os::unix::net::{UnixListener as StdListener, UnixStream as StdStream};
use std::path::{Path, PathBuf};

use egeon_core::ports::local_conn::{BoxFuture, LocalConn, LocalConnError, LocalListener, Probe};
use tokio::net::UnixListener;

/// `sun_path` do macOS tem 104 bytes, com o terminador.
const MAX_PATH: usize = 103;

/// O arquivo no disco: dispositivo e inode.
type FileId = (u64, u64);

pub(super) fn listen(path: &Path) -> Result<Box<dyn LocalListener>, LocalConnError> {
    let len = path.as_os_str().len();
    if len > MAX_PATH {
        return Err(LocalConnError::PathTooLong {
            path: path.display().to_string(),
            len,
            max: MAX_PATH,
        });
    }

    // Entre este teste e o `bind` duas instâncias subindo juntas ainda se
    // atropelam, como no Swift; o porte não fecha essa janela.
    //
    // Duas instâncias do MESMO flavor: a segunda a subir apagava o socket da
    // primeira e punha o dela no lugar; quando saía, levava o arquivo, e a
    // primeira, viva, ficava com um socket que ninguém alcança.
    if let Probe::Alive { pid } = probe(path) {
        return Err(LocalConnError::AlreadyListening { pid });
    }
    // Ninguém atende: o que estiver no caminho é resto de execução anterior.
    match std::fs::remove_file(path) {
        Ok(()) => {}
        Err(error) if error.kind() == io::ErrorKind::NotFound => {}
        Err(error) => return Err(error.into()),
    }

    // O std já cria com CLOEXEC; sem ele o fd de escuta vazaria para todo
    // processo filho, e os filhos aqui são os pty dos agentes, que vivem horas.
    let listener = StdListener::bind(path)?;
    listener.set_nonblocking(true)?;
    let listener = UnixListener::from_std(listener)?;
    let bound = file_id(path).ok_or_else(|| {
        LocalConnError::Io(io::Error::new(
            io::ErrorKind::NotFound,
            "o socket sumiu logo após o bind",
        ))
    })?;

    Ok(Box::new(Listener {
        listener,
        path: path.to_path_buf(),
        bound,
    }))
}

pub(super) fn probe(path: &Path) -> Probe {
    if std::fs::metadata(path).is_err() {
        return Probe::Nobody;
    }
    // Conectar e não escrever nada: é o único teste que separa instância viva de
    // arquivo órfão, e o órfão é o caso comum depois de um crash.
    match StdStream::connect(path) {
        Ok(stream) => Probe::Alive {
            pid: peer_pid(stream.as_raw_fd()),
        },
        Err(_) => Probe::Nobody,
    }
}

struct Listener {
    listener: UnixListener,
    path: PathBuf,
    bound: FileId,
}

impl LocalListener for Listener {
    fn accept(&self) -> BoxFuture<'_, Result<LocalConn, LocalConnError>> {
        Box::pin(async move {
            let (stream, _) = self.listener.accept().await?;
            let fd = stream.as_raw_fd();
            // Quem chamou pode desistir antes da resposta (o gancho do CLI tem
            // `--max-time 1`). Escrever num socket fechado manda SIGPIPE, que por
            // padrão mata o processo sem relatório de crash.
            no_sigpipe(fd);
            Ok(LocalConn {
                peer_pid: peer_pid(fd),
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
        // Só apaga o que é nosso: o arquivo no caminho pode ser o socket de outra
        // instância, e apagá-lo deixaria ELA viva e inalcançável.
        if self.is_current() {
            let _ = std::fs::remove_file(&self.path);
        }
    }
}

fn file_id(path: &Path) -> Option<FileId> {
    let metadata = std::fs::metadata(path).ok()?;
    Some((metadata.dev(), metadata.ino()))
}

/// Pid do processo do outro lado, segundo o kernel.
///
/// A alternativa — o remetente se identificar no pedido — não é verificável: quem
/// monta o `curl` é o agente, e ele pode escrever qualquer endereço ali.
fn peer_pid(fd: RawFd) -> Option<u32> {
    let mut pid: libc::pid_t = 0;
    let mut size = size_of::<libc::pid_t>() as libc::socklen_t;
    // SAFETY: `pid` e `size` são locais vivos com o tamanho declarado.
    let result = unsafe {
        libc::getsockopt(
            fd,
            libc::SOL_LOCAL,
            libc::LOCAL_PEERPID,
            (&mut pid as *mut libc::pid_t).cast(),
            &mut size,
        )
    };
    (result == 0 && pid > 0).then_some(pid as u32)
}

fn no_sigpipe(fd: RawFd) {
    let on: libc::c_int = 1;
    // SAFETY: `on` é um local vivo com o tamanho declarado. Falhar só devolve o
    // SIGPIPE, que o Rust já ignora por padrão em executáveis.
    unsafe {
        libc::setsockopt(
            fd,
            libc::SOL_SOCKET,
            libc::SO_NOSIGPIPE,
            (&on as *const libc::c_int).cast(),
            size_of::<libc::c_int>() as libc::socklen_t,
        );
    }
}
