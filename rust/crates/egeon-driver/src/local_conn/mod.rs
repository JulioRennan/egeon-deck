//! Escuta local: o socket de controle e o pid de quem conecta.

use std::path::Path;

use egeon_core::ports::local_conn::{LocalConnDriver, LocalConnError, LocalListener, Probe};

#[cfg(unix)]
mod unix;

/// O driver de conexão local do sistema em que o app roda.
#[derive(Debug, Default, Clone, Copy)]
pub struct SystemLocalConn;

#[cfg(unix)]
impl LocalConnDriver for SystemLocalConn {
    fn listen(&self, path: &Path) -> Result<Box<dyn LocalListener>, LocalConnError> {
        unix::listen(path)
    }

    fn probe(&self, path: &Path) -> Probe {
        unix::probe(path)
    }
}
