//! Interface da escuta local: o socket de controle, por onde chegam o `egeon`,
//! os ganchos dos agentes e a UI.
//!
//! Implementada por `egeon-driver`. O que varia por plataforma é o meio (socket
//! unix, pipe nomeado) e a forma de o sistema dizer quem está do outro lado da
//! conexão; o HTTP e as rotas por cima são do core.
//!
//! Quem está do outro lado vem do sistema ([`LocalConn::peer_pid`]), nunca do
//! pedido: o remetente que se identifica no corpo pode mentir, e as guardas de
//! cadeia dependem dessa identidade.

use std::future::Future;
use std::path::Path;
use std::pin::Pin;

use thiserror::Error;
use tokio::io::{AsyncRead, AsyncWrite};

pub type BoxFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;

/// Os dois sentidos de uma conexão aceita.
pub trait LocalStream: AsyncRead + AsyncWrite + Send + Unpin {}
impl<T: AsyncRead + AsyncWrite + Send + Unpin> LocalStream for T {}

/// Uma conexão aceita.
pub struct LocalConn {
    pub stream: Box<dyn LocalStream>,
    /// Pid do processo do outro lado, segundo o sistema; `None` se ele não
    /// disse. O processo que abre a conexão (o `egeon`) é neto do shell do
    /// terminal: quem sobe a cadeia até o dono é o core.
    pub peer_pid: Option<u32>,
}

/// O que há atendendo num caminho agora.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Probe {
    /// Ninguém atende: o que estiver no caminho é resto de execução anterior.
    Nobody,
    /// Alguém atende. `pid` é `None` quando atende mas o sistema não disse quem.
    Alive { pid: Option<u32> },
}

#[derive(Debug, Error)]
pub enum LocalConnError {
    #[error("caminho longo demais para o socket ({len} bytes, o limite é {max}): {path}")]
    PathTooLong {
        path: String,
        len: usize,
        max: usize,
    },
    #[error("já há outra instância atendendo neste caminho (pid {pid:?})")]
    AlreadyListening { pid: Option<u32> },
    #[error("falha de sistema: {0}")]
    Io(#[from] std::io::Error),
}

/// Abre escutas locais.
pub trait LocalConnDriver: Send + Sync {
    /// Passa a atender em `path` e guarda o inode do arquivo criado, para depois
    /// saber se ainda é o nosso. A pasta de `path` já existe (criá-la é do core).
    ///
    /// Recusa com [`LocalConnError::AlreadyListening`] se alguém já atende ali;
    /// se o que há é um órfão de crash, apaga e segue. Precisa rodar dentro do
    /// runtime tokio.
    fn listen(&self, path: &Path) -> Result<Box<dyn LocalListener>, LocalConnError>;

    /// Conecta e não escreve nada: é o único teste que separa instância viva de
    /// arquivo órfão.
    fn probe(&self, path: &Path) -> Probe;
}

/// Uma escuta aberta. Largar o valor para de atender e apaga o arquivo do
/// caminho — mas só se ainda for o nosso.
pub trait LocalListener: Send + Sync {
    /// Espera a próxima conexão. Seguro de cancelar. Um erro aqui é de uma
    /// conexão só ou do listener inteiro; quem decide é o core.
    fn accept(&self) -> BoxFuture<'_, Result<LocalConn, LocalConnError>>;

    /// O arquivo no caminho ainda é o que esta escuta criou? `false` quando
    /// sumiu ou virou de outro processo — é o que o vigia do core confere de
    /// tempos em tempos, para religar.
    fn is_current(&self) -> bool;
}
